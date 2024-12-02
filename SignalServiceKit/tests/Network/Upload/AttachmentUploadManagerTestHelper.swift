//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

typealias PerformTSRequestBlock = ((TSRequest, Bool) async throws -> any HTTPResponse)
typealias PerformRequestBlock = ((URLRequest) async throws -> any HTTPResponse)
typealias PerformUploadBlock = ((URLRequest, URL) async throws -> any HTTPResponse)

enum MockRequestType {
    case uploadForm(PerformTSRequestBlock)
    case uploadLocation(PerformRequestBlock)
    case uploadProgress(PerformRequestBlock)
    case uploadTask(PerformUploadBlock)
}

enum MockResultType {
    case uploadForm(TSRequest)
    case uploadLocation(URLRequest)
    case uploadProgress(URLRequest)
    case uploadTask(URLRequest)
}

class AttachmentUploadManagerMockHelper {
    var mockDate = Date()
    lazy var mockDateProvider = { return self.mockDate }
    var mockDB = InMemoryDB()
    var mockURLSession = AttachmentUploadManagerImpl.Mocks.URLSession()
    var mockNetworkManager = AttachmentUploadManagerImpl.Mocks.NetworkManager(libsignalNet: nil)
    var mockServiceManager = OWSSignalServiceMock()
    var mockChatConnectionManager = AttachmentUploadManagerImpl.Mocks.ChatConnectionManager()
    var mockFileSystem = AttachmentUploadManagerImpl.Mocks.FileSystem()
    var mockInteractionStore = MockInteractionStore()
    var mockStoryStore = StoryStoreImpl()
    var mockAttachmentStore = AttachmentStoreMock()
    lazy var mockAttachmentUploadStore = AttachmentUploadStoreMock(attachmentStore: mockAttachmentStore)
    var mockAttachmentThumbnailService = MockAttachmentThumbnailService()
    var mockAttachmentEncrypter = AttachmentUploadManagerImpl.Mocks.AttachmentEncrypter()
    var messageBackupKeyMaterial = AttachmentUploadManagerImpl.Mocks.MessageBackupKeyMaterial()
    var messageBackupRequestManager = AttachmentUploadManagerImpl.Mocks.MessageBackupRequestManager()
    var mockRemoteConfigProvider = MockRemoteConfigProvider()

    var capturedRequests = [MockResultType]()

    // List of auth requests.
    var authFormRequestBlock = [MockRequestType]()

    // Map of auth header to resume location maps
    var authToUploadRequestMockMap = [String: [MockRequestType]]()

    // auth set the active location Requests (and the active URL)
    var activeUploadRequestMocks = [MockRequestType]()

    func setup(encryptedSize: UInt32, unencryptedSize: UInt32) {
        setup(
            encryptedUploadSize: encryptedSize,
            mockAttachment: MockAttachmentStream.mock(
                streamInfo: .mock(
                    encryptedByteCount: encryptedSize,
                    unencryptedByteCount: unencryptedSize
                )
            ).attachment
        )
    }

    func setup(
        encryptedUploadSize: UInt32,
        mockAttachment: Attachment
    ) {

        self.mockAttachmentStore.mockFetcher = { _ in
            return mockAttachment
        }
        self.mockFileSystem.size = Int(clamping: encryptedUploadSize)

        mockServiceManager.mockUrlSessionBuilder = { (info: SignalServiceInfo, endpoint: OWSURLSessionEndpoint, config: URLSessionConfiguration? ) in
            return self.mockURLSession
        }

        mockNetworkManager.performRequestBlock = { request, canUseWebSocket in
            let item = self.authFormRequestBlock.removeFirst()
            guard case let .uploadForm(authDataTaskBlock) = item else {
                return .init(error: OWSAssertionError("Mock request missing"))
            }
            self.capturedRequests.append(.uploadForm(request))
            return Promise.wrapAsync { try await authDataTaskBlock(request, canUseWebSocket) }
        }

        mockURLSession.performRequestBlock = { request in
            switch self.activeUploadRequestMocks.removeFirst() {
            case .uploadLocation(let requestBlock):
                self.capturedRequests.append(.uploadLocation(request))
                return try await requestBlock(request)
            case .uploadProgress(let requestBlock):
                self.capturedRequests.append(.uploadProgress(request))
                return try await requestBlock(request)
            case .uploadForm, .uploadTask:
                throw OWSAssertionError("Mock request missing")
            }
        }

        mockURLSession.performUploadFileBlock = { request, url, _, _ in
            guard case let .uploadTask(requestBlock) = self.activeUploadRequestMocks.removeFirst() else {
                throw OWSAssertionError("Mock request missing")
            }
            self.capturedRequests.append(.uploadTask(request))
            return try await requestBlock(request, url)
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
            return HTTPResponseImpl(
                requestUrl: request.url!,
                status: statusCode,
                headers: OWSHttpHeaders(),
                bodyData: try! JSONEncoder().encode(form)
            )
        }))
        return (authString, location)
    }

    func addResumeLocationMock(auth: String, statusCode: Int = 201) -> String {
        // Create a random, yet identifiable URL.  Helps with debugging the captured requests.
        let location = "https://resume/location/\(UUID().uuidString)"
        enqueue(auth: auth, request: .uploadLocation({ request in
            let headers = [ "Location": location ]
            return HTTPResponseImpl(
                requestUrl: request.url!,
                status: statusCode,
                headers: OWSHttpHeaders(httpHeaders: headers, overwriteOnConflict: true),
                bodyData: nil
            )
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

            return HTTPResponseImpl(
                requestUrl: request.url!,
                status: statusCode,
                headers: OWSHttpHeaders(httpHeaders: headers, overwriteOnConflict: true),
                bodyData: nil
            )
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
                throw OWSHTTPError.networkFailure
            case .failure:
                statusCode = 500
                fallthrough // Use the same response code as success
            case .success:
                return HTTPResponseImpl(
                    requestUrl: request.url!,
                    status: statusCode,
                    headers: OWSHttpHeaders(),
                    bodyData: nil
                )
            }
        }))
    }

    private func enqueue(auth: String, request: MockRequestType) {
        var mocks = authToUploadRequestMockMap[auth] ?? [MockRequestType]()
        mocks.append(request)
        authToUploadRequestMockMap[auth] = mocks
    }
}
