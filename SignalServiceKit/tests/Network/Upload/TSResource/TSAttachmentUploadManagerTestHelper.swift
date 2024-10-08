//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

class TSAttachmentUploadManagerMockHelper {
    var mockDB = InMemoryDB()
    var mockURLSession = AttachmentUploadManagerImpl.Mocks.URLSession()
    var mockNetworkManager = AttachmentUploadManagerImpl.Mocks.NetworkManager(libsignalNet: nil)
    var mockServiceManager = OWSSignalServiceMock()
    var mockChatConnectionManager = AttachmentUploadManagerImpl.Mocks.ChatConnectionManager()
    var mockAttachmentEncrypter = AttachmentUploadManagerImpl.Mocks.AttachmentEncrypter()
    var mockBlurHash = TSAttachmentUpload.Mocks.BlurHash()
    var mockFileSystem = AttachmentUploadManagerImpl.Mocks.FileSystem()
    var mockInteractionStore = MockInteractionStore()
    var mockResourceStore = TSAttachmentUploadStoreMock()

    var capturedRequests = [MockResultType]()

    // List of auth requests.
    var authFormRequestBlock = [MockRequestType]()

    // Map of auth header to resume location maps
    var authToUploadRequestMockMap = [String: [MockRequestType]]()

    // auth set the active location Requests (and the active URL)
    var activeUploadRequestMocks = [MockRequestType]()

    func setup(filename: String, size: Int) {

        self.mockResourceStore.filename = filename
        self.mockResourceStore.size = size
        self.mockFileSystem.size = size

        mockServiceManager.mockUrlSessionBuilder = { (info: SignalServiceInfo, endpoint: OWSURLSessionEndpoint, config: URLSessionConfiguration? ) in
            return self.mockURLSession
        }

        mockAttachmentEncrypter.encryptAttachmentBlock = { _, _ in
            EncryptionMetadata(key: Data(), digest: Data(), length: size, plaintextLength: size)
        }

        mockNetworkManager.performRequestBlock = { request, canUseWebSocket in
            let item = self.authFormRequestBlock.removeFirst()
            guard case let .uploadForm(authDataTaskBlock) = item else {
                return .init(error: OWSAssertionError("Mock request missing"))
            }
            self.capturedRequests.append(.uploadForm(request))
            return authDataTaskBlock(request, canUseWebSocket)
        }

        mockURLSession.promiseForDataTaskBlock = { request in
            switch self.activeUploadRequestMocks.removeFirst() {
            case .uploadLocation(let requestBlock):
                self.capturedRequests.append(.uploadLocation(request))
                return requestBlock(request)
            case .uploadProgress(let requestBlock):
                self.capturedRequests.append(.uploadProgress(request))
                return requestBlock(request)
            case .uploadForm, .uploadTask:
                return .init(error: OWSAssertionError("Mock request missing"))
            }
        }

        mockURLSession.promiseForUploadFileTaskBlock = { request, url, _, _ in
            guard case let .uploadTask(requestBlock) = self.activeUploadRequestMocks.removeFirst() else {
                return .init(error: OWSAssertionError("Mock request missing"))
            }
            self.capturedRequests.append(.uploadTask(request))
            return requestBlock(request, url)
        }
    }

    func addFormRequestMock(version: UInt32, statusCode: Int = 200) -> (auth: String, location: String) {
        let authString = UUID().uuidString
        // Create a random, yet identifiable URL.  Helps with debugging the captured requests.
        let location = "https://upload/location/\(UUID().uuidString)"
        authFormRequestBlock.append(.uploadForm({ request, _ in
            let headers = [ "Auth": authString, ]
            let form = Upload.Form(
                headers: headers,
                signedUploadLocation: location,
                cdnKey: UUID().uuidString,
                cdnNumber: version
            )
            self.activeUploadRequestMocks = self.authToUploadRequestMockMap[authString] ?? .init()
            return .value(HTTPResponseImpl(
                requestUrl: request.url!,
                status: statusCode,
                headers: OWSHttpHeaders(),
                bodyData: try! JSONEncoder().encode(form)
            ))
        }))
        return (authString, location)
    }

    func addResumeLocationMock(auth: String, statusCode: Int = 201) -> String {
        // Create a random, yet identifiable URL.  Helps with debugging the captured requests.
        let location = "https://resume/location/\(UUID().uuidString)"
        enqueue(auth: auth, request: .uploadLocation({ request in
            let headers = [ "Location": location ]
            return .value(HTTPResponseImpl(
                requestUrl: request.url!,
                status: statusCode,
                headers: OWSHttpHeaders(httpHeaders: headers, overwriteOnConflict: true),
                bodyData: nil
            ))
        }))
        return location
    }

    enum ResumeProgressType {
        case complete
        case progress(count: Int)
        case newUpload
        case missingRange
        case malformedRange
        case otherStatusCode(Int)
    }
    func addResumeProgressMock(auth: String, location: String, type: ResumeProgressType) {
        enqueue(auth: auth, request: .uploadProgress({ request in
            var headers = ["Location": "\(location)"]
            var statusCode = 308

            switch type {
            case .progress(let count):
                headers["Range"] = "bytes=0-\(count)"
            case .newUpload:
                break
            case .missingRange:
                headers["Range"] = "bytes="
            case .malformedRange:
                headers["Range"] = "bytes=0-baddata"
            case .otherStatusCode(let code):
                statusCode = code
            case .complete:
                statusCode = 201 // This could also be a 200
            }

            return .value(HTTPResponseImpl(
                requestUrl: request.url!,
                status: statusCode,
                headers: OWSHttpHeaders(httpHeaders: headers, overwriteOnConflict: true),
                bodyData: nil
            ))
        }))
    }

    enum UploadResultType {
        case success
        case failure
        case networkError
    }
    func addUploadRequestMock(auth: String, location: String, type: UploadResultType) {
        enqueue(auth: auth, request: .uploadTask({ request, url in
            var statusCode = 200
            switch type {
            case .networkError:
                return .init(error: OWSHTTPError.networkFailure(requestUrl: request.url!))
            case .failure:
                statusCode = 500
                fallthrough // Use the same response code as success
            case .success:
                return .value(HTTPResponseImpl(
                    requestUrl: request.url!,
                    status: statusCode,
                    headers: OWSHttpHeaders(),
                    bodyData: nil
                ))
            }
        }))
    }

    private func enqueue(auth: String, request: MockRequestType) {
        var mocks = authToUploadRequestMockMap[auth] ?? [MockRequestType]()
        mocks.append(request)
        authToUploadRequestMockMap[auth] = mocks
    }
}

class TSAttachmentUploadStoreMock: TSResourceStoreMock, TSResourceUploadStore {
    var filename: String!
    var size: Int!
    var uploadedAttachments = [TSAttachmentStream]()

    override func fetch(_ ids: [TSResourceId], tx: DBReadTransaction) -> [TSResource] {
        return ids.map { _ in
            return TSAttachmentStream(
                contentType: "image/jpeg",
                byteCount: UInt32(size),
                sourceFilename: filename,
                caption: nil,
                attachmentType: .default,
                albumMessageId: nil
            )
        }
    }

    func updateAsUploaded(
        attachmentStream: TSResourceStream,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) {
        uploadedAttachments.append(attachmentStream as! TSAttachmentStream)
    }
}
