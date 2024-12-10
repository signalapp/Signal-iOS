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

        typealias MessageBackupKeyMaterial = _AttachmentUploadManager_MessageBackupKeyMaterialMock
        typealias MessageBackupRequestManager = _AttachmentUploadManager_MessageBackupRequestManagerMock
    }
}

class _Upload_AttachmentEncrypterMock: Upload.Shims.AttachmentEncrypter {

    var encryptAttachmentBlock: ((URL, URL) -> EncryptionMetadata)?
    func encryptAttachment(at unencryptedUrl: URL, output encryptedUrl: URL) throws -> EncryptionMetadata {
        return encryptAttachmentBlock!(unencryptedUrl, encryptedUrl)
    }

    var decryptAttachmentBlock: ((URL, EncryptionMetadata, URL) -> Void)?
    func decryptAttachment(at encryptedUrl: URL, metadata: EncryptionMetadata, output: URL) throws {
        return decryptAttachmentBlock!(encryptedUrl, metadata, output)
    }
}

class _Upload_FileSystemMock: Upload.Shims.FileSystem {
    var size: Int!

    func temporaryFileUrl() -> URL { return URL(string: "file://")! }

    func deleteFile(url: URL) throws { }

    func createTempFileSlice(url: URL, start: Int) throws -> (URL, Int) {
        return (url, size - start)
    }
}

class _AttachmentUploadManager_NetworkManagerMock: NetworkManager {

    var performRequestBlock: ((TSRequest, Bool) -> Promise<HTTPResponse>)?

    override func asyncRequest(_ request: TSRequest, canUseWebSocket: Bool = false) async throws -> any HTTPResponse {
        return try await performRequestBlock!(request, canUseWebSocket).awaitable()
    }

    override func makePromise(request: TSRequest, canUseWebSocket: Bool = false) -> Promise<HTTPResponse> {
        return performRequestBlock!(request, canUseWebSocket)
    }
}

public class _AttachmentUploadManager_OWSURLSessionMock: BaseOWSURLSessionMock {

    public var performUploadDataBlock: ((URLRequest, Data, OWSProgressSource?) async throws -> any HTTPResponse)?
    public override func performUpload(request: URLRequest, requestData: Data, progress: OWSProgressSource?) async throws -> any HTTPResponse {
        return try await performUploadDataBlock!(request, requestData, progress)
    }

    public var performUploadFileBlock: ((URLRequest, URL, Bool, OWSProgressSource?) async throws -> any HTTPResponse)?
    public override func performUpload(request: URLRequest, fileUrl: URL, ignoreAppExpiry: Bool, progress: OWSProgressSource?) async throws -> any HTTPResponse {
        return try await performUploadFileBlock!(request, fileUrl, ignoreAppExpiry, progress)
    }

    public var performRequestBlock: ((URLRequest) async throws -> any HTTPResponse)?
    public override func performRequest(request: URLRequest, ignoreAppExpiry: Bool) async throws -> any HTTPResponse {
        return try await performRequestBlock!(request)
    }
}

class _AttachmentUploadManager_ChatConnectionManagerMock: ChatConnectionManager {
    var hasEmptiedInitialQueue: Bool { true }
    var identifiedConnectionState: OWSChatConnectionState { .open }
    func waitForIdentifiedConnectionToOpen() async throws { }
    func canMakeRequests(connectionType: OWSChatConnectionType) -> Bool { true }
    func makeRequest(_ request: TSRequest) async throws -> HTTPResponse { fatalError() }
    func didReceivePush() { }
}

class _AttachmentUploadManager_MessageBackupKeyMaterialMock: MessageBackupKeyMaterial {
    func backupKey(
        type: MessageBackupAuthCredentialType,
        tx: DBReadTransaction
    ) throws(MessageBackupKeyMaterialError) -> BackupKey {
        fatalError("Unimplemented for tests")
    }

    func mediaEncryptionMetadata(
        mediaName: String,
        type: MediaTierEncryptionType,
        tx: any DBReadTransaction
    ) throws(MessageBackupKeyMaterialError) -> MediaTierEncryptionMetadata {
        return .init(type: type, mediaId: Data(), hmacKey: Data(), aesKey: Data())
    }
}

class _AttachmentUploadManager_MessageBackupRequestManagerMock: MessageBackupRequestManager {
    func fetchBackupServiceAuth(
        for type: MessageBackupAuthCredentialType,
        localAci: Aci,
        auth: ChatServiceAuth
    ) async throws -> MessageBackupServiceAuth {
        fatalError("Unimplemented for tests")
    }

    func reserveBackupId(localAci: Aci, auth: ChatServiceAuth) async throws { }

    func registerBackupKeys(localAci: Aci, auth: ChatServiceAuth) async throws {}

    func fetchBackupUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form {
        fatalError("Unimplemented for tests")
    }

    func fetchBackupMediaAttachmentUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form {
        fatalError("Unimplemented for tests")
    }

    func fetchBackupInfo(auth: MessageBackupServiceAuth) async throws -> MessageBackupRemoteInfo {
        fatalError("Unimplemented for tests")
    }

    func refreshBackupInfo(auth: MessageBackupServiceAuth) async throws { }

    func fetchMediaTierCdnRequestMetadata(cdn: Int32, auth: MessageBackupServiceAuth) async throws -> MediaTierReadCredential {
        fatalError("Unimplemented for tests")
    }

    func fetchBackupRequestMetadata(auth: MessageBackupServiceAuth) async throws -> BackupReadCredential {
        fatalError("Unimplemented for tests")
    }

    func copyToMediaTier(
        item: MessageBackup.Request.MediaItem,
        auth: MessageBackupServiceAuth
    ) async throws -> UInt32 {
        return 3
    }

    func copyToMediaTier(
        items: [MessageBackup.Request.MediaItem],
        auth: MessageBackupServiceAuth
    ) async throws -> [MessageBackup.Response.BatchedBackupMediaResult] {
        return []
    }

    func listMediaObjects(
        cursor: String?,
        limit: UInt32?,
        auth: MessageBackupServiceAuth
    ) async throws -> MessageBackup.Response.ListMediaResult {
        fatalError("Unimplemented for tests")
    }

    func deleteMediaObjects(
        objects: [MessageBackup.Request.DeleteMediaTarget],
        auth: MessageBackupServiceAuth
    ) async throws {
    }

    func redeemReceipt(receiptCredentialPresentation: Data) async throws {
    }
}

// MARK: - AttachmentStore

class AttachmentStoreMock: AttachmentStoreImpl {

    var mockFetcher: ((Attachment.IDType) -> Attachment)?

    override func fetch(ids: [Attachment.IDType], tx: DBReadTransaction) -> [Attachment] {
        return ids.map(mockFetcher!)
    }
}

class AttachmentUploadStoreMock: AttachmentUploadStoreImpl {

    var uploadedAttachments = [AttachmentStream]()

    override func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info: Attachment.TransitTierInfo,
        tx: SignalServiceKit.DBWriteTransaction
    ) throws {
        uploadedAttachments.append(attachmentStream)
    }

    override func markTransitTierUploadExpired(
        attachment: Attachment,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    override func markUploadedToMediaTier(
        attachment: Attachment,
        mediaTierInfo: Attachment.MediaTierInfo,
        tx: DBWriteTransaction
    ) throws {}

    override func markMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {}

    override func markThumbnailUploadedToMediaTier(
        attachment: Attachment,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo,
        tx: DBWriteTransaction
    ) throws {}

    override func markThumbnailMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {}

    override func upsert(record: AttachmentUploadRecord, tx: DBWriteTransaction) throws { }

    func removeRecord(for attachmentId: Attachment.IDType, tx: DBWriteTransaction) throws {}

    func fetchAttachmentUploadRecord(for attachmentId: Attachment.IDType, tx: DBReadTransaction) throws -> AttachmentUploadRecord? {
        return nil
    }

    override func removeRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBWriteTransaction
    ) throws { }

    override func fetchAttachmentUploadRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBReadTransaction
    ) throws -> AttachmentUploadRecord? {
        return nil
    }
}
