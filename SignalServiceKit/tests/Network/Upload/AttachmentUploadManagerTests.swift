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
        super.setUp()
        helper = AttachmentUploadManagerMockHelper()
        uploadManager = AttachmentUploadManagerImpl(
            attachmentEncrypter: helper.mockAttachmentEncrypter,
            attachmentStore: helper.mockAttachmentStore,
            attachmentUploadStore: helper.mockAttachmentUploadStore,
            attachmentThumbnailService: helper.mockAttachmentThumbnailService,
            chatConnectionManager: helper.mockChatConnectionManager,
            dateProvider: helper.mockDateProvider,
            db: helper.mockDB,
            fileSystem: helper.mockFileSystem,
            interactionStore: helper.mockInteractionStore,
            messageBackupKeyMaterial: helper.messageBackupKeyMaterial,
            messageBackupRequestManager: helper.messageBackupRequestManager,
            networkManager: helper.mockNetworkManager,
            remoteConfigProvider: helper.mockRemoteConfigProvider,
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
        // 2. Successful upload
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadLocation(request) = helper.capturedRequests[1] {
            XCTAssertEqual(request.url!.absoluteString, uploadLocation)
            XCTAssertEqual(request.httpMethod, "POST")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "0")
        } else { XCTFail("Unexpected request encountered.") }

        if case let .uploadTask(request) = helper.capturedRequests[2] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(encryptedSize)")
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

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

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
        XCTAssertEqual(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount, unencryptedSize)
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

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadTask(request) = helper.capturedRequests[4] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(encryptedSize)")
            XCTAssertNil(request.allHTTPHeaderFields!["Content-Range"])
        } else { XCTFail("Unexpected request encountered.") }
        XCTAssertEqual(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount, unencryptedSize)
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

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadTask(request) = helper.capturedRequests[6] {
            XCTAssertEqual(request.url!.absoluteString, location2)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(encryptedSize)")
            XCTAssertNil(request.allHTTPHeaderFields!["Content-Range"])
        } else { XCTFail("Unexpected request encountered.") }
        XCTAssertEqual(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount, unencryptedSize)
    }

    // MARK: Testing reupload strategies

    func testCannotBeUploaded() async throws {
        let uploadTimestamp = Date(timeIntervalSinceNow: -10000)
        helper.mockDate = uploadTimestamp.addingTimeInterval(Upload.Constants.uploadReuseWindow / 2)

        // Set up an attachment that isn't a stream.
        helper.mockAttachmentStore.mockFetcher = { _ in
            return MockAttachment.mock(
                streamInfo: nil,
                transitTierInfo: .mock(
                    uploadTimestamp: uploadTimestamp.ows_millisecondsSince1970
                )
            )
        }

        do {
            try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)
            XCTFail("Should fail to upload!")
        } catch {
            // Success
        }
    }

    func testAlreadyUploaded() async throws {
        // Set up an already uploaded attachment that is still in the time window.
        let uploadTimestamp = Date(timeIntervalSinceNow: -10000)
        helper.mockDate = uploadTimestamp.addingTimeInterval(Upload.Constants.uploadReuseWindow / 2)
        helper.mockAttachmentStore.mockFetcher = { _ in
            return MockAttachmentStream.mock(
                transitTierInfo: .mock(
                    uploadTimestamp: uploadTimestamp.ows_millisecondsSince1970
                )
            ).attachment
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        XCTAssertTrue(helper.capturedRequests.isEmpty)
    }

    func testUseLocalEncryptionInfo() async throws {
        // Set up an attachment we've never uploaded so we reuse the local stream info.
        let encryptedSize: UInt32 = 27
        helper.setup(
            encryptedUploadSize: encryptedSize,
            mockAttachment: MockAttachmentStream.mock(
                streamInfo: .mock(encryptedByteCount: encryptedSize),
                transitTierInfo: nil,
                mediaTierInfo: nil
            ).attachment
        )

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, uploadLocation) = helper.addFormRequestMock(version: 2)
        // 1. Mock UploadLocation request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Successful upload
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadLocation(request) = helper.capturedRequests[1] {
            XCTAssertEqual(request.url!.absoluteString, uploadLocation)
            XCTAssertEqual(request.httpMethod, "POST")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "0")
        } else { XCTFail("Unexpected request encountered.") }

        if case let .uploadTask(request) = helper.capturedRequests[2] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(encryptedSize)")
        } else { XCTFail("Unexpected request encountered.") }
    }

    func testUseRotatedEncryptionInfo() async throws {
        // Set up an attachment with an expired window so we freshly upload.
        let encryptedSize: UInt32 = 22
        // We should use fresh encryption, so set these to intentionally
        // non matching sizes.
        let streamInfo = Attachment.StreamInfo.mock(encryptedByteCount: encryptedSize + 1)
        let transitTierInfo = Attachment.TransitTierInfo.mock(
            uploadTimestamp: helper.mockDate
                .addingTimeInterval(Upload.Constants.uploadReuseWindow * -2)
                .ows_millisecondsSince1970,
            unencryptedByteCount: encryptedSize + 2
        )

        let attachment = MockAttachmentStream.mock(
            streamInfo: streamInfo,
            transitTierInfo: transitTierInfo,
            mediaTierInfo: nil
        ).attachment
        helper.setup(
            encryptedUploadSize: encryptedSize,
            mockAttachment: attachment
        )

        var didDecrypt = false
        helper.mockAttachmentEncrypter.decryptAttachmentBlock = { _, encryptionMetadata, _ in
            didDecrypt = true
            XCTAssertEqual(encryptionMetadata.key, attachment.encryptionKey)
        }
        var didEncrypt = false
        helper.mockAttachmentEncrypter.encryptAttachmentBlock = { _, _ in
            didEncrypt = true
            return EncryptionMetadata(
                key: Data(),
                digest: Data(),
                length: Int(encryptedSize),
                plaintextLength: Int(streamInfo.unencryptedByteCount)
            )
        }

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, uploadLocation) = helper.addFormRequestMock(version: 2)
        // 1. Mock UploadLocation request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Successful upload
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadLocation(request) = helper.capturedRequests[1] {
            XCTAssertEqual(request.url!.absoluteString, uploadLocation)
            XCTAssertEqual(request.httpMethod, "POST")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "0")
        } else { XCTFail("Unexpected request encountered.") }

        if case let .uploadTask(request) = helper.capturedRequests[2] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(encryptedSize)")
        } else { XCTFail("Unexpected request encountered.") }

        XCTAssertTrue(didDecrypt)
        XCTAssertTrue(didEncrypt)
    }

    func testUseRotatedEncryptionInfo_MediaTierInfoExists() async throws {
        // Set up an attachment with no transit tier upload, but media tier info so we reupload.
        let encryptedSize: UInt32 = 22
        // We should use fresh encryption, so set these to intentionally
        // non matching sizes.
        let streamInfo = Attachment.StreamInfo.mock(encryptedByteCount: encryptedSize + 1)
        let attachment = MockAttachmentStream.mock(
            streamInfo: streamInfo,
            transitTierInfo: nil,
            mediaTierInfo: .mock()
        ).attachment
        helper.setup(
            encryptedUploadSize: encryptedSize,
            mockAttachment: attachment
        )

        var didDecrypt = false
        helper.mockAttachmentEncrypter.decryptAttachmentBlock = { _, encryptionMetadata, _ in
            didDecrypt = true
            XCTAssertEqual(encryptionMetadata.key, attachment.encryptionKey)
        }
        var didEncrypt = false
        helper.mockAttachmentEncrypter.encryptAttachmentBlock = { _, _ in
            didEncrypt = true
            return EncryptionMetadata(
                key: Data(),
                digest: Data(),
                length: Int(encryptedSize),
                plaintextLength: Int(streamInfo.unencryptedByteCount)
            )
        }

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        let (auth, uploadLocation) = helper.addFormRequestMock(version: 2)
        // 1. Mock UploadLocation request
        let location = helper.addResumeLocationMock(auth: auth)
        // 2. Successful upload
        helper.addUploadRequestMock(auth: auth, location: location, type: .success)

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadLocation(request) = helper.capturedRequests[1] {
            XCTAssertEqual(request.url!.absoluteString, uploadLocation)
            XCTAssertEqual(request.httpMethod, "POST")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "0")
        } else { XCTFail("Unexpected request encountered.") }

        if case let .uploadTask(request) = helper.capturedRequests[2] {
            XCTAssertEqual(request.url!.absoluteString, location)
            XCTAssertEqual(request.httpMethod, "PUT")

            XCTAssertEqual(request.allHTTPHeaderFields!["Content-Length"], "\(encryptedSize)")
        } else { XCTFail("Unexpected request encountered.") }

        XCTAssertTrue(didDecrypt)
        XCTAssertTrue(didEncrypt)
    }
}
