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
            accountKeyStore: helper.mockAccountKeyStore,
            attachmentEncrypter: helper.mockAttachmentEncrypter,
            attachmentStore: helper.mockAttachmentStore,
            attachmentUploadStore: helper.mockAttachmentUploadStore,
            attachmentThumbnailService: helper.mockAttachmentThumbnailService,
            backupRequestManager: helper.mockBackupRequestManager,
            dateProvider: helper.mockDateProvider,
            db: helper.mockDB,
            fileSystem: helper.mockFileSystem,
            interactionStore: helper.mockInteractionStore,
            networkManager: helper.mockNetworkManager,
            remoteConfigProvider: helper.mockRemoteConfigProvider,
            signalService: helper.mockServiceManager,
            sleepTimer: helper.mockSleepTimer,
            storyStore: helper.mockStoryStore,
        )
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testBasicUpload(cdn: CDNEndpoint) async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        let attachmentID = helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Mock UploadLocation request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, uploadLocation, resumeLocation in
            // 2. Successful upload
            helper.addUploadRequestMock(auth: auth, location: resumeLocation, type: .success)
        }

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

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
        let attachmentID = helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Upload location request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, _, location in
            // 2. Fail the upload with a network error
            helper.addUploadRequestMock(auth: auth, location: location, type: .networkError)
            // 3. Fetch the progress (10 of 20 bytes)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .progress(count: firstUpload))
            // 4. Complete the upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

        if case let .uploadTask(request) = helper.capturedUploadRequests.last {
            #expect(request.httpMethod == attempt.resumeUploadHttpMethod)
            switch cdn {
            case .cdn2:
                #expect(request.url!.absoluteString == attempt.fetchedUploadLocation)
                let expectedLength = Int(encryptedSize) - firstUpload
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(expectedLength)")

                let nextByte = firstUpload
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
    func testBasicChunkedUpload(cdn: CDNEndpoint) async throws {
        let chunkSize = helper.mockFileSystem.maxFileChunkSizeBytes()
        let encryptedSize: Int = chunkSize + 1
        let unencryptedSize = encryptedSize

        let attachmentID = helper.setup(encryptedSize: UInt32(encryptedSize), unencryptedSize: UInt32(unencryptedSize))

        let attempt2 = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, _, location in
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .progress(count: Int(chunkSize)))
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

        if case let .uploadTask(request) = helper.capturedUploadRequests[0] {
            #expect(request.httpMethod == attempt2.uploadHttpMethod)
            switch cdn {
            case .cdn2:
                #expect(request.url!.absoluteString == attempt2.fetchedUploadLocation)
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(chunkSize)")
                #expect(request.allHTTPHeaderFields!["content-range"] == nil)
            case .cdn3:
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(chunkSize)")
                #expect(request.allHTTPHeaderFields!["Upload-Offset"] == "0")

                #expect(request.url!.absoluteString == attempt2.fetchedUploadLocation)

                #expect(request.allHTTPHeaderFields![UploadEndpointCDN3.Constants.checksumHeaderKey] != nil)
                #expect(request.allHTTPHeaderFields!["upload-length"] == "\(encryptedSize)")
            }
        } else { Issue.record("Unexpected request encountered.") }

        if case let .uploadTask(request) = helper.capturedUploadRequests[1] {
            #expect(request.httpMethod == attempt2.resumeUploadHttpMethod)
            switch cdn {
            case .cdn2:
                #expect(request.url!.absoluteString == attempt2.fetchedUploadLocation)
                let expectedLength = encryptedSize - chunkSize
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(expectedLength)")
                #expect(request.allHTTPHeaderFields!["content-range"] == "bytes \(chunkSize)-\(chunkSize)/\(encryptedSize)")
            case .cdn3:
                let expectedLength = encryptedSize - chunkSize
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(expectedLength)")
                #expect(request.allHTTPHeaderFields!["Upload-Offset"] == "\(chunkSize)")

                #expect(request.url!.absoluteString == attempt2.resumeUploadURL)

                #expect(request.allHTTPHeaderFields![UploadEndpointCDN3.Constants.checksumHeaderKey] == nil)
                #expect(request.allHTTPHeaderFields!["upload-length"] == nil)
            }
        } else { Issue.record("Unexpected request encountered.") }
        #expect(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount == unencryptedSize)
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testMultipleChunkedUpload(cdn: CDNEndpoint) async throws {
        let chunkSize = helper.mockFileSystem.maxFileChunkSizeBytes()
        let encryptedSize: Int = (chunkSize * 2) + 10
        let unencryptedSize: Int = encryptedSize + 1 // Just to make it different than encrypted size

        let attachmentID = helper.setup(encryptedSize: UInt32(encryptedSize), unencryptedSize: UInt32(unencryptedSize))

        let attempt2 = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, _, location in
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .progress(count: Int(chunkSize)))
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
            helper.addResumeProgressMock(cdn: cdn, auth: auth, location: location, type: .progress(count: Int(chunkSize * 2)))
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

        if case let .uploadTask(request) = helper.capturedUploadRequests[0] {
            #expect(request.httpMethod == attempt2.uploadHttpMethod)
            switch cdn {
            case .cdn2:
                #expect(request.url!.absoluteString == attempt2.fetchedUploadLocation)
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(chunkSize)")
                #expect(request.allHTTPHeaderFields!["content-range"] == nil)
            case .cdn3:
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(chunkSize)")
                #expect(request.allHTTPHeaderFields!["Upload-Offset"] == "0")

                #expect(request.url!.absoluteString == attempt2.fetchedUploadLocation)

                #expect(request.allHTTPHeaderFields![UploadEndpointCDN3.Constants.checksumHeaderKey] != nil)
                #expect(request.allHTTPHeaderFields!["upload-length"] == "\(encryptedSize)")
            }
        } else { Issue.record("Unexpected request encountered.") }

        if case let .uploadTask(request) = helper.capturedUploadRequests[1] {
            #expect(request.httpMethod == attempt2.resumeUploadHttpMethod)
            switch cdn {
            case .cdn2:
                #expect(request.url!.absoluteString == attempt2.fetchedUploadLocation)
                let startRange = chunkSize
                let endRange = (chunkSize * 2) - 1 // This is an inclusive range, so subtract one from the end range
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(chunkSize)")
                #expect(request.allHTTPHeaderFields!["content-range"] == "bytes \(startRange)-\(endRange)/\(encryptedSize)")
            case .cdn3:
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "\(chunkSize)")
                #expect(request.allHTTPHeaderFields!["Upload-Offset"] == "\(chunkSize)")

                #expect(request.url!.absoluteString == attempt2.resumeUploadURL)

                #expect(request.allHTTPHeaderFields![UploadEndpointCDN3.Constants.checksumHeaderKey] == nil)
                #expect(request.allHTTPHeaderFields!["upload-length"] == nil)
            }
        } else { Issue.record("Unexpected request encountered.") }

        if case let .uploadTask(request) = helper.capturedUploadRequests[2] {
            #expect(request.httpMethod == attempt2.resumeUploadHttpMethod)
            switch cdn {
            case .cdn2:
                #expect(request.url!.absoluteString == attempt2.fetchedUploadLocation)
                let startRange = chunkSize * 2
                let endRange = encryptedSize - 1 // This is an inclusive range, so subtract one from the end range
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "10")
                #expect(request.allHTTPHeaderFields!["content-range"] == "bytes \(startRange)-\(endRange)/\(encryptedSize)")
            case .cdn3:
                #expect(request.allHTTPHeaderFields!["Content-Length"] == "10")
                #expect(request.allHTTPHeaderFields!["Upload-Offset"] == "\(chunkSize * 2)")

                #expect(request.url!.absoluteString == attempt2.resumeUploadURL)

                #expect(request.allHTTPHeaderFields![UploadEndpointCDN3.Constants.checksumHeaderKey] == nil)
                #expect(request.allHTTPHeaderFields!["upload-length"] == nil)
            }
        } else { Issue.record("Unexpected request encountered.") }
        #expect(helper.mockAttachmentUploadStore.uploadedAttachments.first!.unencryptedByteCount == unencryptedSize)
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testBadRangePrefixRestartUpload(cdn: CDNEndpoint) async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32
        let attachmentID = helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

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

        try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

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
        let attachmentID = helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

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

        try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

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
        let attachmentID = helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

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

        try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

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
        let attachmentID = helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

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

        try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

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
        let attachmentID = helper.setup(encryptedSize: encryptedSize, unencryptedSize: unencryptedSize)

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

        try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

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
        let attachmentID = helper.insertMockAttachment(
            MockAttachment.mock(
                streamInfo: nil,
                transitTierInfo: .mock(
                    uploadTimestamp: uploadTimestamp.ows_millisecondsSince1970,
                ),
            ),
        )

        do {
            try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)
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
        let attachmentID = helper.insertMockAttachment(
            MockAttachmentStream.mock(
                transitTierInfo: .mock(
                    uploadTimestamp: uploadTimestamp.ows_millisecondsSince1970,
                ),
            ).attachment,
        )

        try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

        #expect(helper.capturedRequests.isEmpty)
    }

    @Test(arguments: CDNEndpoint.allCases)
    func testUseLocalEncryptionInfo(cdn: CDNEndpoint) async throws {
        // Set up an attachment we've never uploaded so we reuse the local stream info.
        let encryptedSize: UInt32 = 27
        let attachmentID = helper.setup(
            encryptedUploadSize: encryptedSize,
            mockAttachment: MockAttachmentStream.mock(
                streamInfo: .mock(encryptedByteCount: encryptedSize),
                transitTierInfo: nil,
                mediaTierInfo: nil,
            ).attachment,
        )

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Mock UploadLocation request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, uploadLocation, location in
            // 2. Successful upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

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
            unencryptedByteCount: encryptedSize + 2,
        )

        let attachment = MockAttachmentStream.mock(
            streamInfo: streamInfo,
            transitTierInfo: transitTierInfo,
            mediaTierInfo: nil,
        ).attachment
        let attachmentID = helper.setup(
            encryptedUploadSize: encryptedSize,
            mockAttachment: attachment,
        )

        var didDecrypt = false
        helper.mockAttachmentEncrypter.decryptAttachmentBlock = { _, encryptionMetadata, _ in
            didDecrypt = true
            #expect(encryptionMetadata.key.combinedKey == attachment.encryptionKey)
        }
        var didEncrypt = false
        helper.mockAttachmentEncrypter.encryptAttachmentBlock = { _, _ in
            didEncrypt = true
            return EncryptionMetadata(
                key: try! AttachmentKey(combinedKey: Data(count: 64)),
                digest: Data(),
                encryptedLength: UInt64(safeCast: encryptedSize),
                plaintextLength: UInt64(safeCast: streamInfo.unencryptedByteCount),
            )
        }

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Mock UploadLocation request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, uploadLocation, location in
            // 2. Successful upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

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
            mediaTierInfo: .mock(),
        ).attachment
        let attachmentID = helper.setup(
            encryptedUploadSize: encryptedSize,
            mockAttachment: attachment,
        )

        var didDecrypt = false
        helper.mockAttachmentEncrypter.decryptAttachmentBlock = { _, encryptionMetadata, _ in
            didDecrypt = true
            #expect(encryptionMetadata.key.combinedKey == attachment.encryptionKey)
        }
        var didEncrypt = false
        helper.mockAttachmentEncrypter.encryptAttachmentBlock = { _, _ in
            didEncrypt = true
            return EncryptionMetadata(
                key: try! AttachmentKey(combinedKey: Data(count: 64)),
                digest: Data(),
                encryptedLength: UInt64(safeCast: encryptedSize),
                plaintextLength: UInt64(safeCast: streamInfo.unencryptedByteCount),
            )
        }

        // Indexed to line up with helper.capturedRequests.
        // 0. Mock the form request
        // 1. Mock UploadLocation request
        let attempt = helper.addUploadFormAndLocationRequestMock(cdn: cdn) { auth, uploadLocation, location in
            // 2. Successful upload
            helper.addUploadRequestMock(auth: auth, location: location, type: .success)
        }

        _ = try await uploadManager.uploadTransitTierAttachment(attachmentId: attachmentID)

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
