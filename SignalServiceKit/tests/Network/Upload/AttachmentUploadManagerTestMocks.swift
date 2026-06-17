//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
@testable public import SignalServiceKit

extension AttachmentUploadManagerImpl {
    enum Mocks {
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

public class _AttachmentUploadManager_OWSURLSessionMock: BaseOWSURLSessionMock {

    public var performUploadDataBlock: ((URLRequest, Data, UInt64, OWSURLSession.ProgressBlock) async throws -> HTTPResponse)?
    override public func performUpload(request: URLRequest, requestData: Data, maxResponseSize: UInt64, progressBlock: OWSURLSession.ProgressBlock) async throws -> HTTPResponse {
        return try await performUploadDataBlock!(request, requestData, maxResponseSize, progressBlock)
    }

    public var performRequestBlock: ((URLRequest, UInt64, Bool) async throws -> HTTPResponse)?
    override public func performRequest(request: URLRequest, maxResponseSize: UInt64, ignoreAppExpiry: Bool) async throws -> HTTPResponse {
        return try await performRequestBlock!(request, maxResponseSize, ignoreAppExpiry)
    }
}

struct MockAuthMessageService: AuthMessagesService {
    var performRequestBlock: (@Sendable () throws -> UploadForm)
    func getUploadForm(uploadSize: UInt64) async throws -> UploadForm {
        try performRequestBlock()
    }

    func sendMessage(
        to recipient: ServiceId,
        timestamp: UInt64,
        contents: [SingleOutboundUnsealedMessage],
        onlineOnly: Bool,
        urgent: Bool,
    ) async throws {
        owsFail("not implemented")
    }

    func sendSyncMessage(
        timestamp: UInt64,
        contents: [SingleOutboundUnsealedMessage],
        urgent: Bool,
    ) async throws {
        owsFail("not implemented")
    }
}

class _AttachmentUploadManager_ChatConnectionManagerMock: ChatConnectionManagerMock {
    var performRequestBlock: (@Sendable () throws -> UploadForm)?
    override func withAuthServiceImpl<Service, Output>(
        _ service: Service,
        timeout: TimeInterval,
        do callback: @escaping (Service.Api) async throws -> Output,
    ) async throws -> Output where Service: AuthServiceSelector {
        let service = MockAuthMessageService(performRequestBlock: performRequestBlock!)
        return try await callback(service as! Service.Api)
    }
}

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

    func fetchBackupMediaAttachmentUploadForm(
        encryptedByteLength: UInt32,
        auth: BackupServiceAuth,
        logger: PrefixedLogger,
    ) async throws -> Upload.Form {
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
