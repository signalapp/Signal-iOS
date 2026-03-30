//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
@testable public import SignalServiceKit

extension AttachmentUploadManagerImpl {
    enum Mocks {
        typealias NetworkManager = _AttachmentUploadManager_NetworkManagerMock
        typealias URLSession = _AttachmentUploadManager_OWSURLSessionMock
        typealias ChatConnectionManager = _AttachmentUploadManager_ChatConnectionManagerMock

        typealias AttachmentEncrypter = _Upload_AttachmentEncrypterMock
        typealias FileSystem = _Upload_FileSystemMock

        typealias BackupRequestManager = _AttachmentUploadManager_BackupRequestManagerMock

        typealias SleepTimer = _Upload_SleepTimerMock
    }
}

class _Upload_AttachmentEncrypterMock: Upload.Shims.AttachmentEncrypter {

    var encryptAttachmentBlock: ((URL, URL) -> EncryptionMetadata)?
    func encryptAttachment(at unencryptedUrl: URL, output encryptedUrl: URL) throws -> EncryptionMetadata {
        return encryptAttachmentBlock!(unencryptedUrl, encryptedUrl)
    }

    var decryptAttachmentBlock: ((URL, DecryptionMetadata, URL) -> Void)?
    func decryptAttachment(at encryptedUrl: URL, metadata: DecryptionMetadata, output: URL) throws {
        return decryptAttachmentBlock!(encryptedUrl, metadata, output)
    }
}

class _Upload_FileSystemMock: Upload.Shims.FileSystem {
    var size: Int!

    func temporaryFileUrl() -> URL { return URL(string: "file://")! }

    func fileOrFolderExists(url: URL) -> Bool {
        true
    }

    func deleteFile(url: URL) throws { }

    func maxFileChunkSizeBytes() -> Int { 32 }

    func readMemoryMappedFileData(url: URL) throws -> Data {
        return Data(repeating: 0, count: size)
    }
}

class _Upload_SleepTimerMock: Upload.Shims.SleepTimer {
    var requestedDelays = [TimeInterval]()
    func sleep(for delay: TimeInterval) async throws {
        requestedDelays.append(delay)
    }
}

class _AttachmentUploadManager_NetworkManagerMock: NetworkManager {

    var performRequestBlock: ((TSRequest) -> Promise<HTTPResponse>)?

    override func asyncRequestImpl(_ request: TSRequest, retryPolicy: RetryPolicy) async throws -> HTTPResponse {
        return try await performRequestBlock!(request).awaitable()
    }
}

public class _AttachmentUploadManager_OWSURLSessionMock: BaseOWSURLSessionMock {

    public var performUploadDataBlock: ((URLRequest, Data, OWSProgressSource?) async throws -> HTTPResponse)?
    override public func performUpload(request: URLRequest, requestData: Data, progress: OWSProgressSource?) async throws -> HTTPResponse {
        return try await performUploadDataBlock!(request, requestData, progress)
    }

    public var performUploadFileBlock: ((URLRequest, URL, Bool, OWSProgressSource?) async throws -> HTTPResponse)?
    override public func performUpload(request: URLRequest, fileUrl: URL, ignoreAppExpiry: Bool, progress: OWSProgressSource?) async throws -> HTTPResponse {
        return try await performUploadFileBlock!(request, fileUrl, ignoreAppExpiry, progress)
    }

    public var performRequestBlock: ((URLRequest) async throws -> HTTPResponse)?
    override public func performRequest(request: URLRequest, ignoreAppExpiry: Bool) async throws -> HTTPResponse {
        return try await performRequestBlock!(request)
    }
}

class _AttachmentUploadManager_ChatConnectionManagerMock: ChatConnectionManagerMock {}

class _AttachmentUploadManager_BackupRequestManagerMock: BackupRequestManager {
    func fetchBackupServiceAuthForRegistration(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth: ChatServiceAuth,
        logger: PrefixedLogger,
    ) async throws -> BackupServiceAuth {
        fatalError("Unimplemented for tests")
    }

    func fetchBackupServiceAuth(
        for key: BackupKeyMaterial,
        localAci: Aci,
        auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool,
        logger: PrefixedLogger,
    ) async throws -> BackupServiceAuth {
        fatalError("Unimplemented for tests")
    }

    func reserveBackupId(localAci: Aci, auth: ChatServiceAuth) async throws { }

    func fetchBackupUploadForm(
        backupByteLength: UInt32,
        auth: BackupServiceAuth,
        logger: PrefixedLogger,
    ) async throws -> Upload.Form {
        fatalError("Unimplemented for tests")
    }

    func fetchBackupMediaAttachmentUploadForm(auth: BackupServiceAuth, logger: PrefixedLogger) async throws -> Upload.Form {
        fatalError("Unimplemented for tests")
    }

    func fetchMediaTierCdnRequestMetadata(cdn: Int32, auth: BackupServiceAuth, logger: PrefixedLogger) async throws -> MediaTierReadCredential {
        fatalError("Unimplemented for tests")
    }

    func fetchBackupRequestMetadata(auth: BackupServiceAuth, logger: PrefixedLogger) async throws -> BackupReadCredential {
        fatalError("Unimplemented for tests")
    }

    func copyToMediaTier(
        item: BackupArchive.Request.MediaItem,
        auth: BackupServiceAuth,
        logger: PrefixedLogger,
    ) async throws -> UInt32 {
        return 3
    }

    func copyToMediaTier(
        items: [BackupArchive.Request.MediaItem],
        auth: BackupServiceAuth,
        logger: PrefixedLogger,
    ) async throws -> [BackupArchive.Response.BatchedBackupMediaResult] {
        return []
    }

    func listMediaObjects(
        cursor: String?,
        limit: UInt32?,
        auth: BackupServiceAuth,
        logger: PrefixedLogger,
    ) async throws -> BackupArchive.Response.ListMediaResult {
        fatalError("Unimplemented for tests")
    }

    func deleteMediaObjects(
        objects: [BackupArchive.Request.DeleteMediaTarget],
        auth: BackupServiceAuth,
        logger: PrefixedLogger,
    ) async throws {
    }

    func redeemReceipt(receiptCredentialPresentation: Data, logger: PrefixedLogger) async throws {
    }

    func fetchSVRBAuthCredential(
        key: SignalServiceKit.MessageRootBackupKey,
        chatServiceAuth auth: SignalServiceKit.ChatServiceAuth,
        forceRefresh: Bool,
        logger: PrefixedLogger,
    ) async throws -> LibSignalClient.Auth {
        return LibSignalClient.Auth(username: "", password: "")
    }
}

// MARK: -

class AttachmentUploadStoreMock: AttachmentUploadStore {
    override func upsert(record: AttachmentUploadRecord, tx: DBWriteTransaction) { }

    override func removeRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBWriteTransaction,
    ) { }

    override func fetchAttachmentUploadRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBReadTransaction,
    ) -> AttachmentUploadRecord? {
        return nil
    }
}
