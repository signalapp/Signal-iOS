//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

extension AttachmentUploadManagerImpl {
    enum Mocks {
        typealias NetworkManager = _AttachmentUploadManager_NetworkManagerMock
        typealias URLSession = _AttachmentUploadManager_OWSURLSessionMock
        typealias ChatConnectionManager = _AttachmentUploadManager_ChatConnectionManagerMock

        typealias AttachmentEncrypter = _Upload_AttachmentEncrypterMock
        typealias FileSystem = _Upload_FileSystemMock
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

    override func makePromise(request: TSRequest, canUseWebSocket: Bool = false) -> Promise<HTTPResponse> {
        return performRequestBlock!(request, canUseWebSocket)
    }
}

public class _AttachmentUploadManager_OWSURLSessionMock: BaseOWSURLSessionMock {

    public var promiseForUploadDataTaskBlock: ((URLRequest, Data, ProgressBlock?) -> Promise<HTTPResponse>)?
    public override func uploadTaskPromise(request: URLRequest, data requestData: Data, progress progressBlock: ProgressBlock?) -> Promise<HTTPResponse> {
        return promiseForUploadDataTaskBlock!(request, requestData, progressBlock)
    }

    public var promiseForUploadFileTaskBlock: ((URLRequest, URL, Bool, ProgressBlock?) -> Promise<HTTPResponse>)?
    public override func uploadTaskPromise(
        request: URLRequest,
        fileUrl: URL,
        ignoreAppExpiry: Bool = false,
        progress progressBlock: ProgressBlock? = nil
    ) -> Promise<HTTPResponse> {
        return promiseForUploadFileTaskBlock!(request, fileUrl, ignoreAppExpiry, progressBlock)
    }

    public var promiseForDataTaskBlock: ((URLRequest) -> Promise<HTTPResponse>)?
    public override func dataTaskPromise(request: URLRequest, ignoreAppExpiry: Bool = false) -> Promise<HTTPResponse> {
        return promiseForDataTaskBlock!(request)
    }
}

class _AttachmentUploadManager_ChatConnectionManagerMock: ChatConnectionManager {
    var hasEmptiedInitialQueue: Bool { true }
    var identifiedConnectionState: OWSChatConnectionState { .open }
    func waitForIdentifiedConnectionToOpen() async throws { }
    func cycleSocket() { }
    func canMakeRequests(connectionType: OWSChatConnectionType) -> Bool { true }
    func makeRequest(_ request: TSRequest) async throws -> HTTPResponse { fatalError() }
    func didReceivePush() { }
}

// MARK: - AttachmentStore

class AttachmentUploadStoreMock: AttachmentStoreMock, AttachmentUploadStore {
    var uploadedAttachments = [AttachmentStream]()

    var mockFetcher: ((Attachment.IDType) -> Attachment)?

    override func fetch(ids: [Attachment.IDType], tx: DBReadTransaction) -> [Attachment] {
        return ids.map(mockFetcher!)
    }

    func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info: Attachment.TransitTierInfo,
        tx: SignalServiceKit.DBWriteTransaction
    ) throws {
        uploadedAttachments.append(attachmentStream)
    }
}
