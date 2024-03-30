//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class AttachmentUploadManagerTests: XCTestCase {
    var uploadManager: AttachmentUploadManager!
    var helper: AttachmentUploadManagerMockHelper!

    override func setUp() {
        helper = AttachmentUploadManagerMockHelper()
        uploadManager = AttachmentUploadManagerImpl(
            attachmentStore: helper.mockAttachmentStore,
            chatConnectionManager: helper.mockChatConnectionManager,
            db: helper.mockDB,
            fileSystem: helper.mockFileSystem,
            interactionStore: helper.mockInteractionStore,
            networkManager: helper.mockNetworkManager,
            signalService: helper.mockServiceManager,
            storyStore: helper.mockStoryStore
        )
    }

    func testBasicUpload_CDN2_v3() async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, uploadLocation) = helper.addFormRequestMock(version: 2)
        // 1. Mock UploadLocation request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Successful download
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        _ = try await uploadManager.uploadAttachment(attachmentId: 1)

        if case let .uploadLocation(request) = helper.capturedRequests[1] {
            XCTAssertEqual(request.url!.absoluteString, uploadLocation)
            XCTAssertEqual(request.httpMethod, "POST")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "0")
        } else { XCTFail("Unexpected request encountered.") }

        if case let .uploadTask(request) = helper.capturedRequests[2] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")

            XCTAssertNotNil(request.allHTTPHeaderFields!["Content-Length"], "\(encryptedSize)")
        } else { XCTFail("Unexpected request encountered.") }
    }

    func testBasicRestartUpload_v3_CDN2() async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        let firstUpload = 10
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, _) = helper.addFormRequestMock(version: 2)
        // 1. Upload location request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Fail the upload with a network error
        helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
        // 3. Fetch the progress (10 of 20 bytes)
        helper.addResumeProgressMock(auth: auth, location: location, type: .progress(count: firstUpload))
        // 4. Complete the upload
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        try await uploadManager.uploadAttachment(attachmentId: 1)

        if case let .uploadTask(request) = helper.capturedRequests[4] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")
            // the '- 1' is because the length reports is inclusive (so 0-10 is 11 bytes)
            let expectedLength = Int(encryptedSize) - firstUpload - 1
            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(expectedLength)")

            let nextByte = firstUpload + 1
            let lastByte = encryptedSize - 1
            XCTAssertEqual(request.allHTTPHeaderFields!["content-range"], "bytes \(nextByte)-\(lastByte)/\(encryptedSize)")
        } else { XCTFail("Unexpected request encountered.") }
        XCTAssertEqual(helper.mockAttachmentStore.uploadedAttachments.first!.unenecryptedByteCount, unencryptedSize)
    }

    func testBadRangePrefixRestartUpload_v3_CDN2() async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, _) = helper.addFormRequestMock(version: 2)
        // 1. Upload location request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Fail the upload with a network error
        helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
        // 3. Fetch the progress (10 of 20 bytes)
        helper.addResumeProgressMock(auth: auth, location: location, type: .missingRange)
        // 4. Complete the upload
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        try await uploadManager.uploadAttachment(attachmentId: 1)

        if case let .uploadTask(request) = helper.capturedRequests[4] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(encryptedSize)")
            XCTAssertNil(request.allHTTPHeaderFields!["Content-Range"])
        } else { XCTFail("Unexpected request encountered.") }
        XCTAssertEqual(helper.mockAttachmentStore.uploadedAttachments.first!.unenecryptedByteCount, unencryptedSize)
    }

    func testFullRestartUpload_v3_CDN2() async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, _) = helper.addFormRequestMock(version: 2)
        // 1. Upload location request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Fail the upload with a network error
        helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
        // 3. Fetch the progress (10 of 20 bytes)
        helper.addResumeProgressMock(auth: auth, location: location, type: .malformedRange)

        // 4. Mock the form request
        let (auth2, _) = helper.addFormRequestMock(version: 2)
        // 5. Upload location request
        let location2 = helper.addResumeLocationMock(auth: auth2)
        // 6. Complete the upload
        helper.addUploadRequestMock(auth: auth2, location: location2, type: .success)

        try await uploadManager.uploadAttachment(attachmentId: 1)

        if case let .uploadTask(request) = helper.capturedRequests[6] {
            XCTAssertEqual(request.url!.absoluteString, location2)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(encryptedSize)")
            XCTAssertNil(request.allHTTPHeaderFields!["Content-Range"])
        } else { XCTFail("Unexpected request encountered.") }
        XCTAssertEqual(helper.mockAttachmentStore.uploadedAttachments.first!.unenecryptedByteCount, unencryptedSize)
    }
}
