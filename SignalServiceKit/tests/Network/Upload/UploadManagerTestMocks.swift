//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

extension Upload {
    enum Mocks {
        typealias AttachmentStore = _UploadManager_AttachmentStoreMock
        typealias NetworkManager = _UploadManager_NetworkManagerMock
        typealias URLSession = _UploadManager_OWSURLSessionMock
        typealias SocketManager = _UploadManager_SocketManagerMock

        typealias AttachmentEncrypter = _UploadManager_AttachmentEncrypterMock
        typealias BlurHash = _Upload_BlurHashMock
        typealias FileSystem = _Upload_FileSystemMock
    }
}

class _UploadManager_AttachmentStoreMock: AttachmentStoreMock {
    var filename: String!
    var size: Int!
    var uploadedAttachments = [TSAttachmentStream]()

    override func fetchAttachmentStream(
        uniqueId: String,
        tx: DBReadTransaction
    ) -> TSAttachmentStream? {
        return TSAttachmentStream(
            contentType: "image/jpeg",
            byteCount: UInt32(size),
            sourceFilename: filename,
            caption: nil,
            attachmentType: .default,
            albumMessageId: nil
        )
    }

    override func updateAsUploaded(
        attachmentStream: TSAttachmentStream,
        encryptionKey: Data,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        uploadedAttachments.append(attachmentStream)
    }
}

class _Upload_BlurHashMock: Upload.Shims.BlurHash {
    func ensureBlurHash(attachmentStream: TSAttachmentStream) async throws {
        return
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

class _UploadManager_NetworkManagerMock: NetworkManager {

    var performRequestBlock: ((TSRequest, Bool) -> Promise<HTTPResponse>)?

    override func makePromise(request: TSRequest, canUseWebSocket: Bool = false) -> Promise<HTTPResponse> {
        return performRequestBlock!(request, canUseWebSocket)
    }
}

class _UploadManager_AttachmentEncrypterMock: Upload.Shims.AttachmentEncrypter {

    var encryptAttachmentBlock: ((URL, URL) -> EncryptionMetadata)?
    func encryptAttachment(at unencryptedUrl: URL, output encryptedUrl: URL) throws -> EncryptionMetadata {
        return encryptAttachmentBlock!(unencryptedUrl, encryptedUrl)
    }
}

public class _UploadManager_OWSURLSessionMock: BaseOWSURLSessionMock {

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

class _UploadManager_SocketManagerMock: SocketManager {
    var isAnySocketOpen: Bool { true }
    var hasEmptiedInitialQueue: Bool { true }
    func socketState(forType webSocketType: OWSWebSocketType) -> OWSWebSocketState { .open }
    func cycleSocket() { }
    func canMakeRequests(webSocketType: OWSWebSocketType) -> Bool { true }
    func makeRequestPromise(request: TSRequest) -> Promise<HTTPResponse> { fatalError() }
    func didReceivePush() { }
}
