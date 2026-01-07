//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit

typealias PerformTSRequestBlock = (TSRequest) async throws -> HTTPResponse
typealias PerformRequestBlock = (URLRequest) async throws -> HTTPResponse
typealias PerformUploadBlock = (URLRequest, Data, OWSProgressSource?) async throws -> HTTPResponse

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

struct MockUploadAttempt {
    let cdn: CDNEndpoint
    let auth: String
    let form: Upload.Form
    let formUploadLocation: String
    let fetchedUploadLocation: String

    var resumeUploadURL: String {
        switch cdn {
        case .cdn2: return fetchedUploadLocation
        case .cdn3: return fetchedUploadLocation + "/" + form.cdnKey
        }
    }

    var uploadHttpMethod: String {
        switch cdn {
        case .cdn2: return "PUT"
        case .cdn3: return "POST"
        }
    }

    var resumeUploadHttpMethod: String {
        switch cdn {
        case .cdn2: return "PUT"
        case .cdn3: return "PATCH"
        }
    }

    var fetchedUploadSuccesStatusCode: Int {
        switch cdn {
        case .cdn2: return 201
        case .cdn3: return 200
        }
    }
}

enum CDNEndpoint: UInt32, CaseIterable {
    case cdn2 = 2
    case cdn3 = 3
}

class AttachmentUploadManagerMockHelper {
    let mockAccountKeyStore = AccountKeyStore(
        backupSettingsStore: BackupSettingsStore(),
    )
    var mockDate = Date()
    lazy var mockDateProvider = { return self.mockDate }
    var mockDB = InMemoryDB()
    var mockURLSession = AttachmentUploadManagerImpl.Mocks.URLSession()
    var mockNetworkManager = AttachmentUploadManagerImpl.Mocks.NetworkManager(appReadiness: AppReadinessMock(), libsignalNet: nil)
    var mockServiceManager = OWSSignalServiceMock()
    var mockChatConnectionManager = AttachmentUploadManagerImpl.Mocks.ChatConnectionManager()
    var mockFileSystem = AttachmentUploadManagerImpl.Mocks.FileSystem()
    var mockInteractionStore = MockInteractionStore()
    var mockStoryStore = StoryStoreImpl()
    var mockAttachmentStore = AttachmentStore()
    lazy var mockAttachmentUploadStore = AttachmentUploadStoreMock(attachmentStore: mockAttachmentStore)
    var mockAttachmentThumbnailService = MockAttachmentThumbnailService()
    var mockAttachmentEncrypter = AttachmentUploadManagerImpl.Mocks.AttachmentEncrypter()
    var mockBackupRequestManager = AttachmentUploadManagerImpl.Mocks.BackupRequestManager()
    var mockRemoteConfigProvider = MockRemoteConfigProvider()
    var mockSleepTimer = AttachmentUploadManagerImpl.Mocks.SleepTimer()

    var capturedRequests = [MockResultType]()
    var capturedFormRequests: [MockResultType] { capturedRequests.filter { if case .uploadForm = $0 { true } else { false }}}
    var capturedLocationRequests: [MockResultType] { capturedRequests.filter { if case .uploadLocation = $0 { true } else { false }}}
    var capturedProgressRequests: [MockResultType] { capturedRequests.filter { if case .uploadProgress = $0 { true } else { false }}}
    var capturedUploadRequests: [MockResultType] { capturedRequests.filter { if case .uploadTask = $0 { true } else { false }}}

    // List of auth requests.
    var authFormRequestBlock = [MockRequestType]()

    // Map of auth header to resume location maps
    var authToUploadRequestMockMap = [String: [MockRequestType]]()

    // auth set the active location Requests (and the active URL)
    var activeUploadRequestMocks = [MockRequestType]()

    func setup(encryptedSize: UInt32, unencryptedSize: UInt32) -> Attachment.IDType {
        return setup(
            encryptedUploadSize: encryptedSize,
            mockAttachment: MockAttachmentStream.mock(
                streamInfo: .mock(
                    encryptedByteCount: encryptedSize,
                    unencryptedByteCount: unencryptedSize,
                ),
            ).attachment,
        )
    }

    func setup(
        encryptedUploadSize: UInt32,
        mockAttachment: Attachment,
    ) -> Attachment.IDType {
        self.mockFileSystem.size = Int(clamping: encryptedUploadSize)

        mockServiceManager.mockUrlSessionBuilder = { (info: SignalServiceInfo, endpoint: OWSURLSessionEndpoint, config: URLSessionConfiguration?) in
            return self.mockURLSession
        }
        mockServiceManager.mockCDNUrlSessionBuilder = { _ in
            return self.mockURLSession
        }

        mockNetworkManager.performRequestBlock = { request in
            let item = self.authFormRequestBlock.removeFirst()
            guard case let .uploadForm(authDataTaskBlock) = item else {
                return .init(error: OWSAssertionError("Mock request missing"))
            }
            self.capturedRequests.append(.uploadForm(request))
            return Promise.wrapAsync { try await authDataTaskBlock(request) }
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

        mockURLSession.performUploadDataBlock = { request, data, progress in
            guard case let .uploadTask(requestBlock) = self.activeUploadRequestMocks.removeFirst() else {
                throw OWSAssertionError("Mock request missing")
            }
            self.capturedRequests.append(.uploadTask(request))
            return try await requestBlock(request, data, progress)
        }

        return insertMockAttachment(mockAttachment)
    }

    func insertMockAttachment(_ attachment: Attachment) -> Attachment.IDType {
        return mockDB.write { tx in
            var record = Attachment.Record(attachment: attachment)
            try! record.insert(tx.database)
            return record.sqliteId!
        }
    }

    func addUploadFormAndLocationRequestMock(
        cdn: CDNEndpoint,
        formStatusCode: Int = 200,
        fetchLocationStatusCode: Int = 201,
        _ uploadMockBuilder: (_ auth: String, _ formUploadLocation: String, _ fetchedUploadLocation: String) -> Void,
    ) -> MockUploadAttempt {
        addFormRequestMock(
            cdn: cdn,
            statusCode: formStatusCode,
        ) { auth, formUploadLoaction in
            addFetchedUploadLocationMock(
                cdn: cdn,
                auth: auth,
                signedUploadLocation: formUploadLoaction,
                statusCode: fetchLocationStatusCode,
            ) { fetchedUploadLocation in
                uploadMockBuilder(auth, formUploadLoaction, fetchedUploadLocation)
            }
        }
    }

    private func addFormRequestMock(
        cdn: CDNEndpoint,
        statusCode: Int = 200,
        _ authedMockBuilder: (_ auth: String, _ location: String) -> (String),
    ) -> MockUploadAttempt {
        let authString = UUID().uuidString
        // Create a random, yet identifiable URL.  Helps with debugging the captured requests.
        let location = "https://upload/formUploadLocation/\(UUID().uuidString)"
        let headers: HttpHeaders = ["Auth": authString]
        let form = Upload.Form(
            headers: headers,
            signedUploadLocation: location,
            cdnKey: UUID().uuidString,
            cdnNumber: cdn.rawValue,
        )
        authFormRequestBlock.append(.uploadForm({ request in
            self.activeUploadRequestMocks = self.authToUploadRequestMockMap[authString] ?? .init()
            return HTTPResponse(
                requestUrl: request.url,
                status: statusCode,
                headers: HttpHeaders(),
                bodyData: try! JSONEncoder().encode(form),
            )
        }))
        return .init(
            cdn: cdn,
            auth: authString,
            form: form,
            formUploadLocation: location,
            fetchedUploadLocation: authedMockBuilder(authString, location),
        )
    }

    private func addFetchedUploadLocationMock(
        cdn: CDNEndpoint,
        auth: String,
        signedUploadLocation: String,
        statusCode: Int,
        _ resumedLocationMockBuilder: (String) -> Void,
    ) -> String {
        let location = {
            switch cdn {
            case .cdn2:
                // Create a random, yet identifiable URL.  Helps with debugging the captured requests.
                let fetchedUploadLocation = "https://upload/fetchedUploadLocation/\(UUID().uuidString)"
                enqueue(auth: auth, request: .uploadLocation({ request in
                    let headers = ["Location": fetchedUploadLocation]
                    return HTTPResponse(
                        requestUrl: request.url!,
                        status: statusCode,
                        headers: HttpHeaders(httpHeaders: headers, overwriteOnConflict: true),
                        bodyData: nil,
                    )
                }))
                return fetchedUploadLocation
            case .cdn3:
                return signedUploadLocation
            }
        }()
        resumedLocationMockBuilder(location)
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

    func addResumeProgressMock(cdn: CDNEndpoint, auth: String, location: String, type: ResumeProgressType) {
        switch cdn {
        case .cdn2:
            enqueue(auth: auth, request: .uploadProgress({ request in
                var headers = ["Location": "\(location)"]
                var statusCode = 308

                switch type {
                case .progress(let count):
                    // CDN2 has behavior where the range is returned, not the number of bytes uploaded
                    // So we need to adjust this so `count` can mean consistent things across tests.
                    headers["Range"] = "bytes=0-\(count - 1)"
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

                return HTTPResponse(
                    requestUrl: request.url!,
                    status: statusCode,
                    headers: HttpHeaders(httpHeaders: headers, overwriteOnConflict: true),
                    bodyData: nil,
                )
            }))
        case .cdn3:
            enqueue(auth: auth, request: .uploadProgress({ request in
                var headers = ["Tus-Resumable": "1.0.0"]
                var statusCode = 200

                switch type {
                case .progress(let count):
                    headers["upload-offset"] = "\(count)"
                case .newUpload:
                    break
                case .missingRange:
                    break
                case .malformedRange:
                    headers["upload-offset"] = "baddata"
                case .otherStatusCode(let code):
                    statusCode = code
                case .complete:
                    statusCode = 403
                }

                return HTTPResponse(
                    requestUrl: request.url!,
                    status: statusCode,
                    headers: HttpHeaders(httpHeaders: headers, overwriteOnConflict: true),
                    bodyData: nil,
                )
            }))
        }
    }

    enum UploadResultType {
        case success
        case failure(code: Int)
        case networkError
        case networkTimeout
    }

    func addUploadRequestMock(auth: String, location: String, type: UploadResultType, completedCount: UInt64? = nil) {
        enqueue(auth: auth, request: .uploadTask({ request, url, progress in
            if let completedCount {
                progress?.incrementCompletedUnitCount(by: completedCount)
            }
            switch type {
            case .networkTimeout:
                throw OWSHTTPError.networkFailure(.genericTimeout)
            case .networkError:
                throw OWSHTTPError.networkFailure(.genericFailure)
            case .failure(let code):
                throw OWSHTTPError.serviceResponse(.init(
                    requestUrl: URL(string: location)!,
                    responseStatus: code,
                    responseHeaders: HttpHeaders(),
                    responseData: nil,
                ))
            case .success:
                return HTTPResponse(
                    requestUrl: request.url!,
                    status: 200,
                    headers: HttpHeaders(),
                    bodyData: nil,
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
