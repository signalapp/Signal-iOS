//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
@testable import SignalServiceKit

class AttachmentUploadManagerTests {
    var uploadManager: AttachmentUploadManager!
    var helper: AttachmentUploadManagerMockHelper!

    init() {
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
            sleepTimer: helper.mockSleepTimer,
            storyStore: helper.mockStoryStore
        )
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testBasicUpload(cdn: CDNEndpoint) async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Mock UploadLocation request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { (auth, uploadLocation, resumeLocation) in
            // 2. Successful upload
            helper.addUploadRequestMock(auth: auth, location: resumeLocation, type: .success)
        }

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        switch cdn {
        case .cdn2:
            if case let .uploadLocation(request) = helper.capturedRequests[1] {
                #expect(request.url!.absoluteString == attempt.formUploadLocation)
                #expect(request.httpMethod == "POST")

                #expect(request.allHTTPHeaderFields!["Content-Length"] == "0")
            } else { Issue.record("Unexpected request encountered.") }
        case .cdn3:
            #expect(helper.capturedLocationRequests.count == 0)
        }

        if case let .uploadTask(request) = helper.capturedUploadRequests.first {
            #expect(request.url!.absoluteString == attempt.fetchedUploadLocation)
            #expect(request.httpMethod == attempt.uploadHttpMethod)

            #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(encryptedSize)")
        } else { Issue.record("Unexpected request encountered.") }
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testBasicRestartUpload(cdn: CDNEndpoint) async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        let firstUpload = 10
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Upload location request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { (auth, _, location) in
            // 2. Fail the upload with a network error
            helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
            // 3. Fetch the progress (10 of 20 bytes)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .progress(count: firstUpload))
            // 4. Complete the upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.httpMethod == attempt.resumeUploadHttpMethod)
            switch cdn {
            case .cdn2:
                #expect(request.url!.absoluteString == attempt.fetchedUploadLocation)
                // the '- 1' is because the length reports is inclusive (so 0-10 is 11 bytes)
                let expectedLength = Int(encryptedSize) - firstUpload - 1
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(expectedLength)")

                let nextByte = firstUpload + 1
                let lastByte = encryptedSize - 1
                #expect(request.allHTTPHeaderFields!["content-range"] == "bytes \(nextByte)-\(lastByte)/\(encryptedSize)")
            case .cdn3:
                let expectedLength = Int(encryptedSize) - firstUpload
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(expectedLength)")

                #expect(request.url!.absoluteString == attempt.resumeUploadURL)

                #expect(request.allHTTPHeaderFields![UploadEndpointCDN3.Constants.checksumHeaderKey] == nil)
                #expect(request.allHTTPHeaderFields!["Upload-Length"] == nil)
            }
        } else { Issue.record("Unexpected request encountered.") }
        #expect(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount == unencryptedSize)
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testBadRangePrefixRestartUpload(cdn: CDNEndpoint) async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Upload location request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, _, location in
            // 2. Fail the upload with a network error
            helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
            // 3. Fetch the progress (10 of 20 bytes)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .missingRange)

            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.url!.absoluteString == attempt.fetchedUploadLocation)
            #expect(request.httpMethod == attempt.uploadHttpMethod)
            #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(encryptedSize)")
            #expect(request.allHTTPHeaderFields!["Content-Range"] == nil)
        } else { Issue.record("Unexpected request encountered.") }
        #expect(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount == unencryptedSize)
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testFullRestartUpload(cdn: CDNEndpoint) async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Upload location request
        _ = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, _, location in
            // 2. Fail the upload with a network error
            helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
            // 3. Fetch the progress (10 of 20 bytes)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .malformedRange)
        }

        // 4. Mock the form request
        // 5. Upload location request
        let attempt2 = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, _, location in
            // 6. Complete the upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.url!.absoluteString == attempt2.fetchedUploadLocation)
            #expect(request.httpMethod == attempt2.uploadHttpMethod)
            #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(encryptedSize)")
            #expect(request.allHTTPHeaderFields!["Content-Range"] == nil)
        } else { Issue.record("Unexpected request encountered.") }
        #expect(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount == unencryptedSize)
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testFullRestartSwitchingCDNUpload(cdn: CDNEndpoint) async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        let startCDN = cdn
        let finishCDN: CDNEndpoint = {
            switch cdn {
            case .cdn2: return .cdn3
            case .cdn3: return .cdn2
            }
        }()

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Upload location request
        _ = helper.addUploadFormAndLocationRequestMock(cdn: startCDN) { auth, _, location in
            // 2. Fail the upload with a network error
            helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
            // 3. Fetch the progress (10 of 20 bytes)
            helper.addResumeProgressMock(cdn: startCDN, auth: auth, location: location, type: .malformedRange)
        }

        // NOTE: on resume this switches to the other CDN to attempt the download
        // 4. Mock the form request
        // 5. Upload location request
        let attempt2 = helper.addUploadFormAndLocationRequestMock(cdn: finishCDN) { auth, _, location in
            // 6. Complete the upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.url!.absoluteString == attempt2.fetchedUploadLocation)
            #expect(request.httpMethod == attempt2.uploadHttpMethod)
            #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(encryptedSize)")
            #expect(request.allHTTPHeaderFields!["Content-Range"] == nil)
        } else { Issue.record("Unexpected request encountered.") }
        #expect(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount == unencryptedSize)
    }

    /// Test getting a 500 back, and reporting local progress. Each failure should result in an increasing backoff
    @Test(arguments: CDNEndpoint.allCases)
    func testFullRestartUploadAfter500ReportingLocalProgress(cdn: CDNEndpoint) async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Upload location request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, _, location in
            // 2. Fail the upload with a server error
            helper.addUploadRequestMock(auth: auth, location: location, type: .failure(code: 500), completedCount: 20)

            // 3. Fetch the remote progress, but find none
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .missingRange)

            // 4. Fail the upload with a server error
            helper.addUploadRequestMock(auth: auth, location: location, type: .failure(code: 500), completedCount: 20)

            // 5. Fetch the remote progress, but find none
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .missingRange)

            // 6. Fail the upload with a server error
            helper.addUploadRequestMock(auth: auth, location: location, type: .failure(code: 500), completedCount: 20)

            // 7. Fetch the remote progress, but find none
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .missingRange)

            // 8. Succeed the upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success, completedCount: 20)
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        #expect(helper.mockSleepTimer.requestedDelays.count == 3)

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.url!.absoluteString == attempt.fetchedUploadLocation)
            #expect(request.httpMethod == attempt.uploadHttpMethod)
            #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(encryptedSize)")
            #expect(request.allHTTPHeaderFields!["Content-Range"] == nil)
        } else { Issue.record("Unexpected request encountered.") }
        #expect(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount == unencryptedSize)
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testNetworkTimeoutResumeUpload(cdn: CDNEndpoint) async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Upload location request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, _, location in
            // 2. Fail the upload with a server error
            helper.addUploadRequestMock(auth: auth, location: location, type: .networkTimeout, completedCount: nil)

            // 3. Fetch the progress (0 of 20 bytes)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .progress(count: 5))

            // 4. Fail the upload with a second server error
            helper.addUploadRequestMock(auth: auth, location: location, type: .networkTimeout, completedCount: nil)

            // 5. Fetch the progress (0 of 20 bytes)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .progress(count: 10))

            // 6. Fail the upload with another server error
            helper.addUploadRequestMock(auth: auth, location: location, type: .networkTimeout, completedCount: nil)

            // 7. Fetch the progress (0 of 20 bytes)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .progress(count: 15))

            // 8. Succeed the upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success, completedCount: 20)
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        // Since these are network timeouts, and the remote endpoint is showing progress being made
        // there shouldn't be any backoff timers fired.
        #expect(helper.mockSleepTimer.requestedDelays.count == 0)

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.url!.absoluteString == attempt.resumeUploadURL)
            #expect(request.httpMethod == attempt.resumeUploadHttpMethod)
            #expect(request.allHTTPHeaderFields!["Content-Range"] == nil)
        } else { Issue.record("Unexpected request encountered.") }
        #expect(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount == unencryptedSize)
    }

    // MARK: Testing reupload strategies

    @Test
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
            Issue.record("Should fail to upload!")
        } catch {
            // Success
        }
    }

    @Test
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

        #expect(helper.capturedRequests.isEmpty)
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testUseLocalEncryptionInfo(cdn: CDNEndpoint) async throws {
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
        // 1. Mock UploadLocation request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, uploadLocation, location in
            // 2. Successful upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        switch cdn {
        case .cdn2:
            if case let .uploadLocation(request) = helper.capturedRequests[1] {
                #expect(request.url!.absoluteString == attempt.formUploadLocation)
                #expect(request.httpMethod == "POST")

                #expect(request.allHTTPHeaderFields!["Content-Length"] == "0")
            } else { Issue.record("Unexpected request encountered.") }
        case .cdn3:
            #expect(helper.capturedLocationRequests.count == 0)
        }

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.url!.absoluteString == attempt.fetchedUploadLocation)
            #expect(request.httpMethod == attempt.uploadHttpMethod)

            #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(encryptedSize)")
        } else { Issue.record("Unexpected request encountered.") }
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testUseRotatedEncryptionInfo(cdn: CDNEndpoint) async throws {
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
            #expect(encryptionMetadata.key == attachment.encryptionKey)
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
        // 1. Mock UploadLocation request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, uploadLocation, location in
            // 2. Successful upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        switch cdn {
        case .cdn2:
            if case let .uploadLocation(request) = helper.capturedRequests[1] {
                #expect(request.url!.absoluteString == attempt.formUploadLocation)
                #expect(request.httpMethod == "POST")

                #expect(request.allHTTPHeaderFields!["Content-Length"] == "0")
            } else { Issue.record("Unexpected request encountered.") }
        case .cdn3:
            #expect(helper.capturedLocationRequests.count == 0)
        }

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.url!.absoluteString == attempt.fetchedUploadLocation)
            #expect(request.httpMethod == attempt.uploadHttpMethod)

            #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(encryptedSize)")
        } else { Issue.record("Unexpected request encountered.") }

        #expect(didDecrypt)
        #expect(didEncrypt)
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testUseRotatedEncryptionInfo_MediaTierInfoExists(cdn: CDNEndpoint) async throws {
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
            #expect(encryptionMetadata.key == attachment.encryptionKey)
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
        // 1. Mock UploadLocation request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, uploadLocation, location in
            // 2. Successful upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: 1)

        switch cdn {
        case .cdn2:
            if case let .uploadLocation(request) = helper.capturedRequests[1] {
                #expect(request.url!.absoluteString == attempt.formUploadLocation)
                #expect(request.httpMethod == "POST")

                #expect(request.allHTTPHeaderFields!["Content-Length"] == "0")
            } else { Issue.record("Unexpected request encountered.") }
        case .cdn3:
            #expect(helper.capturedLocationRequests.count == 0)
        }

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.url!.absoluteString == attempt.fetchedUploadLocation)
            #expect(request.httpMethod == attempt.uploadHttpMethod)

            #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(encryptedSize)")
        } else { Issue.record("Unexpected request encountered.") }

        #expect(didDecrypt)
        #expect(didEncrypt)
    }
}
