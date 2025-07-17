//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class SystemStoryManagerTest: SSKBaseTest {

    var mockSignalService: OWSSignalServiceMock {
        return SSKEnvironment.shared.signalServiceRef as! OWSSignalServiceMock
    }

    private class MockMessageProcessor: SystemStoryManager.Shims.MessageProcessor {
        func waitForFetchingAndProcessing() -> Guarantee<Void> {
            return .value(())
        }
    }

    var manager: SystemStoryManager!

    override func setUp() {
        super.setUp()
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .forUnitTests,
                tx: tx
            )
        }
        manager = SystemStoryManager(
            appReadiness: AppReadinessMock(),
            fileSystem: OnboardingStoryManagerFilesystemMock.self,
            messageProcessor: MockMessageProcessor(),
            storyMessageFactory: OnboardingStoryManagerStoryMessageFactoryMock.self
        )
    }

    override func tearDown() {
        let flushExpectation = self.expectation(description: "flush")
        DispatchQueue.main.async {
            self.manager.chainedPromise.enqueue { .value(()) }.ensure {
                self.manager = nil
                flushExpectation.fulfill()
            }.cauterize()
        }
        self.wait(for: [flushExpectation], timeout: 60)
        super.tearDown()
    }

    // MARK: - Downloading

    @MainActor
    func testDownloadStory() async throws {
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            let mockSession = MockDownloadSession()
            var dataCount = 0
            mockSession.performRequestSource = { url in
                dataCount += 1
                guard dataCount <= 1 else {
                    XCTFail("Downloading more than once")
                    throw OWSAssertionError("")
                }
                if url.path.hasSuffix(SystemStoryManager.Constants.manifestPath) {
                    return HTTPResponseImpl(
                        requestUrl: url,
                        status: 200,
                        headers: .init(),
                        bodyData: Self.manifestJSON
                    )
                } else {
                    XCTFail("Got invalid download task url")
                    throw OWSAssertionError("")
                }
            }
            var downloadCount = 0
            mockSession.performDownloadSource = { url in
                downloadCount += 1
                guard downloadCount <= Self.imageNames.count else {
                    XCTFail("Downloading more than once")
                    throw OWSAssertionError("")
                }
                XCTAssert(Self.imageNames
                    .map { $0 + SystemStoryManager.Constants.imageExtension }
                    .contains(url.lastPathComponent)
                )
                return OWSUrlDownloadResponse(
                    httpUrlResponse: HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    downloadUrl: URL(fileURLWithPath: url.lastPathComponent)
                )
            }
            return mockSession
        }

        try await manager.enqueueOnboardingStoryDownload().awaitable()

        // The above code triggers unstructured asynchronous operations -- delay
        // the test until those have had a chance to execute.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: ()) }
        }
    }

    @MainActor
    func testDownloadStory_multipleTimes() async throws {
        let continueCounter = AtomicUInt(lock: .init())
        var initialContinuation: CheckedContinuation<Void, Never>?
        var dataCount = 0
        var downloadCount = 0
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            let mockSession = MockDownloadSession()
            mockSession.performRequestSource = { url in
                dataCount += 1
                guard dataCount <= 1 else {
                    XCTFail("Downloading more than once")
                    throw OWSAssertionError("")
                }
                await withCheckedContinuation { continuation in
                    initialContinuation = continuation
                    if continueCounter.increment() == 2 {
                        initialContinuation?.resume()
                    }
                }
                if url.path.hasSuffix(SystemStoryManager.Constants.manifestPath) {
                    return HTTPResponseImpl(
                        requestUrl: url,
                        status: 200,
                        headers: .init(),
                        bodyData: Self.manifestJSON
                    )
                } else {
                    XCTFail("Got invalid download task url")
                    throw OWSAssertionError("")
                }
            }
            mockSession.performDownloadSource = { url in
                downloadCount += 1
                guard downloadCount <= Self.imageNames.count else {
                    XCTFail("Downloading more than once")
                    throw OWSAssertionError("")
                }
                XCTAssert(Self.imageNames
                    .map { $0 + SystemStoryManager.Constants.imageExtension }
                    .contains(url.lastPathComponent)
                )
                return OWSUrlDownloadResponse(
                    httpUrlResponse: HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    downloadUrl: URL(fileURLWithPath: url.lastPathComponent)
                )
            }
            return mockSession
        }

        // Start both
        async let firstDownload: Void = manager.enqueueOnboardingStoryDownload().awaitable()
        async let secondDownload: Void = manager.enqueueOnboardingStoryDownload().awaitable()

        // and then resume the first
        if continueCounter.increment() == 2 {
            initialContinuation!.resume()
        }

        try await firstDownload
        try await secondDownload

        // The above code triggers unstructured asynchronous operations -- delay
        // the test until those have had a chance to execute.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: ()) }
        }

        // After we've fulfilled, try again, which should't redownload.

        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            XCTFail("Should not be issuing another network request.")
            return .init()
        }

        try await manager.enqueueOnboardingStoryDownload().awaitable()

        // The above code triggers unstructured asynchronous operations -- delay
        // the test until those have had a chance to execute.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: ()) }
        }
    }

    // MARK: - Viewed state

    @MainActor
    func testCleanUpViewedStory() async throws {
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            let mockSession = MockDownloadSession()
            var dataCount = 0
            mockSession.performRequestSource = { url in
                dataCount += 1
                guard dataCount <= 1 else {
                    XCTFail("Downloading more than once")
                    throw OWSAssertionError("")
                }
                if url.path.hasSuffix(SystemStoryManager.Constants.manifestPath) {
                    return HTTPResponseImpl(
                        requestUrl: url,
                        status: 200,
                        headers: .init(),
                        bodyData: Self.manifestJSON
                    )
                } else {
                    XCTFail("Got invalid download task url")
                    throw OWSAssertionError("")
                }
            }
            var downloadCount = 0
            mockSession.performDownloadSource = { url in
                downloadCount += 1
                guard downloadCount <= Self.imageNames.count else {
                    XCTFail("Downloading more than once")
                    throw OWSAssertionError("")
                }
                XCTAssert(Self.imageNames
                    .map { $0 + SystemStoryManager.Constants.imageExtension }
                    .contains(url.lastPathComponent)
                )
                return OWSUrlDownloadResponse(
                    httpUrlResponse: HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    downloadUrl: URL(fileURLWithPath: url.lastPathComponent)
                )
            }
            return mockSession
        }

        try await manager.enqueueOnboardingStoryDownload().awaitable()

        // The above code triggers unstructured asynchronous operations -- delay
        // the test until those have had a chance to execute.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: ()) }
        }

        // Mark all the stories viewed.
        let viewedDate = Date().addingTimeInterval(-SystemStoryManager.Constants.postViewingTimeout)
        write { transaction in
            let stories = StoryFinder.storiesForListView(transaction: transaction)
            XCTAssertEqual(stories.count, Self.imageNames.count)
            stories.forEach { story in
                story.markAsViewed(
                    at: viewedDate.ows_millisecondsSince1970,
                    circumstance: .onThisDevice,
                    transaction: transaction
                )
            }
        }

        try write {
            try manager.setHasViewedOnboardingStory(
                source: .local(
                    timestamp: viewedDate.ows_millisecondsSince1970,
                    shouldUpdateStorageService: false
                ),
                transaction: $0
            )
        }

        // The above code triggers unstructured asynchronous operations -- delay
        // the test until those have had a chance to execute.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: ()) }
        }

        try await manager.cleanUpOnboardingStoryIfNeeded().awaitable()

        // Check that stories were indeed deleted.
        read { transaction in
            let stories = StoryFinder.storiesForListView(transaction: transaction)
            XCTAssert(stories.isEmpty)
        }
    }

    @MainActor
    func testLegacyClientDownloadedButUnviewed() async throws {
        // Legacy clients might have downloaded the onboarding story, but not kept track
        // of its viewed state separate from the viewed timestamp on the story messages themselves.
        // Force getting into this state by setting download state as downloaded but not creating
        // any stories or marking viewed state, and check that we clean up and mark viewed.

        // NOTE: if this test ever becomes a nuisance, its okay to delete it. This was written on
        // Oct 5 2022, and only internal clients had the ability to download the onboarding
        // story in this legacy state. Dropping support for those old internal clients is fine eventually.
        try write {
            try manager.markOnboardingStoryDownloaded(messageUniqueIds: ["1234"], transaction: $0)
        }

        // Triggering a download should do the cleanup.
        try await manager.enqueueOnboardingStoryDownload().awaitable()

        // The above code triggers unstructured asynchronous operations -- delay
        // the test until those have had a chance to execute.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: ()) }
        }

        read { transaction in
            if let mockManager = SSKEnvironment.shared.systemStoryManagerRef as? SystemStoryManagerMock {
                mockManager.areSystemStoriesHidden = manager.areSystemStoriesHidden(transaction: transaction)
                mockManager.isOnboardingStoryRead = manager.isOnboardingStoryViewed(transaction: transaction)
            }

            let stories = StoryFinder.unviewedSenderCount(transaction: transaction)
            XCTAssert(stories == 0)
        }
    }

    @MainActor
    func testCleanUpViewedStory_notTimedOut() async throws {
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            let mockSession = MockDownloadSession()
            var dataCount = 0
            mockSession.performRequestSource = { url in
                dataCount += 1
                guard dataCount <= 1 else {
                    XCTFail("Downloading more than once")
                    throw OWSAssertionError("")
                }
                if url.path.hasSuffix(SystemStoryManager.Constants.manifestPath) {
                    return HTTPResponseImpl(
                        requestUrl: url,
                        status: 200,
                        headers: .init(),
                        bodyData: Self.manifestJSON
                    )
                } else {
                    XCTFail("Got invalid download task url")
                    throw OWSAssertionError("")
                }
            }
            var downloadCount = 0
            mockSession.performDownloadSource = { url in
                downloadCount += 1
                guard downloadCount <= Self.imageNames.count else {
                    XCTFail("Downloading more than once")
                    throw OWSAssertionError("")
                }
                XCTAssert(Self.imageNames
                    .map { $0 + SystemStoryManager.Constants.imageExtension }
                    .contains(url.lastPathComponent)
                )
                return OWSUrlDownloadResponse(
                    httpUrlResponse: HTTPURLResponse(
                        url: url,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    downloadUrl: URL(fileURLWithPath: url.lastPathComponent)
                )
            }
            return mockSession
        }

        try await manager.enqueueOnboardingStoryDownload().awaitable()

        // The above code triggers unstructured asynchronous operations -- delay
        // the test until those have had a chance to execute.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: ()) }
        }

        // Mark all the stories viewed, but recently so they aren't timed out.
        let viewedDate = Date()
        write { transaction in
            let stories = StoryFinder.storiesForListView(transaction: transaction)
            XCTAssertEqual(stories.count, Self.imageNames.count)
            stories.forEach { story in
                story.markAsViewed(
                    at: viewedDate.ows_millisecondsSince1970,
                    circumstance: .onThisDevice,
                    transaction: transaction
                )
            }
        }

        // The above code triggers unstructured asynchronous operations -- delay
        // the test until those have had a chance to execute.
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume(returning: ()) }
        }

        try await manager.cleanUpOnboardingStoryIfNeeded().awaitable()

        // Check that stories were not deleted.
        read { transaction in
            let stories = StoryFinder.storiesForListView(transaction: transaction)
            XCTAssertEqual(stories.count, Self.imageNames.count)
        }
    }

    // MARK: - Helpers

    static let imageNames = ["abc", "xyz"]

    static var manifestJSON: Data {
        let imageNamesString = "[\(imageNames.map({ "\"\($0)\""}).joined(separator: ","))]"
        let string = """
        {
            "\(SystemStoryManager.Constants.manifestVersionKey)": "1234",
            "\(SystemStoryManager.Constants.manifestLanguagesKey)": {
                "\(Locale.current.languageCode!)": \(imageNamesString),
                "anImpossibleLanguageCode": [
                    "fail"
                ]
            }
        }
        """
        return string.data(using: .utf8)!
    }
}

private class MockDownloadSession: BaseOWSURLSessionMock {

    var performRequestSource: ((URL) async throws -> any HTTPResponse)?

    override func performRequest(request: URLRequest, ignoreAppExpiry: Bool) async throws -> any HTTPResponse {
        return try await performRequestSource!(request.url!)
    }

    var performDownloadSource: ((URL) async throws -> OWSUrlDownloadResponse)?

    override func performDownload(request: URLRequest, progress: OWSProgressSource?) async throws -> OWSUrlDownloadResponse {
        return try await performDownloadSource!(request.url!)
    }
}
