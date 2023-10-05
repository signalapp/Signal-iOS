//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class SystemStoryManagerTest: SSKBaseTestSwift {

    let timeout: TimeInterval = 5

    var mockSignalService: OWSSignalServiceMock {
        return signalService as! OWSSignalServiceMock
    }

    var scheduler: TestScheduler!

    var manager: SystemStoryManager!

    override func setUp() {
        super.setUp()
        scheduler = TestScheduler()
        databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .init(
                    aci: .init(fromUUID: UUID()),
                    pni: .init(fromUUID: UUID()),
                    e164: .init("+17875550101")!
                ),
                tx: tx.asV2Write
            )
        }
        manager = SystemStoryManager(
            fileSystem: OnboardingStoryManagerFilesystemMock.self,
            schedulers: TestSchedulers(scheduler: scheduler)
        )

        // Make everything sync.
        scheduler.start()
    }

    // MARK: - Downloading

    func testDownloadStory() throws {
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            let mockSession = MockDownloadSession()
            var dataCount = 0
            mockSession.dataPromiseSource = { url in
                dataCount += 1
                guard dataCount <= 1 else {
                    XCTFail("Downloading more than once")
                    return .init(error: OWSAssertionError(""))
                }
                if
                    let url = url,
                    url.path.hasSuffix(SystemStoryManager.Constants.manifestPath)
                {
                    return .value(HTTPResponseImpl(
                        requestUrl: url,
                        status: 200,
                        headers: .init(),
                        bodyData: Self.manifestJSON
                    ))
                } else {
                    XCTFail("Got invalid download task url")
                    return .init(error: OWSAssertionError(""))
                }
            }
            var downloadCount = 0
            mockSession.downloadPromiseSource = { url in
                downloadCount += 1
                guard downloadCount <= Self.imageNames.count else {
                    XCTFail("Downloading more than once")
                    return .init(error: OWSAssertionError(""))
                }
                if let url = url {
                    XCTAssert(Self.imageNames
                        .map { $0 + SystemStoryManager.Constants.imageExtension }
                        .contains(url.lastPathComponent)
                    )
                    return .value(OWSUrlDownloadResponse(
                        task: URLSessionTask(), // doesn't matter
                        httpUrlResponse: HTTPURLResponse(
                            url: url,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: nil
                        )!,
                        downloadUrl: URL(fileURLWithPath: url.lastPathComponent)
                    ))
                } else {
                    XCTFail("No URL")
                    fatalError()
                }
            }
            return mockSession
        }

        let downloadPromise = manager.enqueueOnboardingStoryDownload()
        XCTAssertNotNil(downloadPromise.value)
    }

    func testDownloadStory_multipleTimes() throws {
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            let mockSession = MockDownloadSession()
            var dataCount = 0
            mockSession.dataPromiseSource = { url in
                dataCount += 1
                guard dataCount <= 1 else {
                    XCTFail("Downloading more than once")
                    return .init(error: OWSAssertionError(""))
                }
                if
                    let url = url,
                    url.path.hasSuffix(SystemStoryManager.Constants.manifestPath)
                {
                    return .value(HTTPResponseImpl(
                        requestUrl: url,
                        status: 200,
                        headers: .init(),
                        bodyData: Self.manifestJSON
                    ))
                } else {
                    XCTFail("Got invalid download task url")
                    return .init(error: OWSAssertionError(""))
                }
            }
            var downloadCount = 0
            mockSession.downloadPromiseSource = { url in
                downloadCount += 1
                guard downloadCount <= Self.imageNames.count else {
                    XCTFail("Downloading more than once")
                    return .init(error: OWSAssertionError(""))
                }
                if let url = url {
                    XCTAssert(Self.imageNames
                        .map { $0 + SystemStoryManager.Constants.imageExtension }
                        .contains(url.lastPathComponent)
                    )
                    return .value(OWSUrlDownloadResponse(
                        task: URLSessionTask(), // doesn't matter
                        httpUrlResponse: HTTPURLResponse(
                            url: url,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: nil
                        )!,
                        downloadUrl: URL(fileURLWithPath: url.lastPathComponent)
                    ))
                } else {
                    XCTFail("No URL")
                    fatalError()
                }
            }
            return mockSession
        }

        scheduler.stop()

        let firstDownloadPromise = manager.enqueueOnboardingStoryDownload()

        // before the first can fulfill, start a second
        let secondDownloadPromise = manager.enqueueOnboardingStoryDownload()

        scheduler.start()

        XCTAssertNotNil(firstDownloadPromise.value)
        XCTAssertNotNil(secondDownloadPromise.value)

        // After we've fulfilled, try again, which should't redownload.

        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            XCTFail("Should not be issuing another network request.")
            return .init()
        }

        let thirdDownloadPromise = manager.enqueueOnboardingStoryDownload()

        XCTAssertNotNil(thirdDownloadPromise.value)
    }

    // MARK: - Viewed state

    func testCleanUpViewedStory() throws {
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            let mockSession = MockDownloadSession()
            var dataCount = 0
            mockSession.dataPromiseSource = { url in
                dataCount += 1
                guard dataCount <= 1 else {
                    XCTFail("Downloading more than once")
                    return .init(error: OWSAssertionError(""))
                }
                if
                    let url = url,
                    url.path.hasSuffix(SystemStoryManager.Constants.manifestPath)
                {
                    return .value(HTTPResponseImpl(
                        requestUrl: url,
                        status: 200,
                        headers: .init(),
                        bodyData: Self.manifestJSON
                    ))
                } else {
                    XCTFail("Got invalid download task url")
                    return .init(error: OWSAssertionError(""))
                }
            }
            var downloadCount = 0
            mockSession.downloadPromiseSource = { url in
                downloadCount += 1
                guard downloadCount <= Self.imageNames.count else {
                    XCTFail("Downloading more than once")
                    return .init(error: OWSAssertionError(""))
                }
                if let url = url {
                    XCTAssert(Self.imageNames
                        .map { $0 + SystemStoryManager.Constants.imageExtension }
                        .contains(url.lastPathComponent)
                    )
                    return .value(OWSUrlDownloadResponse(
                        task: URLSessionTask(), // doesn't matter
                        httpUrlResponse: HTTPURLResponse(
                            url: url,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: nil
                        )!,
                        downloadUrl: URL(fileURLWithPath: url.lastPathComponent)
                    ))
                } else {
                    XCTFail("No URL")
                    fatalError()
                }
            }
            return mockSession
        }

        let downloadPromise = manager.enqueueOnboardingStoryDownload()
        XCTAssertNotNil(downloadPromise.value)

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
            try manager.setOnboardingStoryViewedOnThisDevice(
                atTimestamp: viewedDate.ows_millisecondsSince1970,
                transaction: $0
            )
        }

        let cleanupPromise = manager.cleanUpOnboardingStoryIfNeeded()
        XCTAssertNotNil(cleanupPromise.value)

        // Check that stories were indeed deleted.
        read { transaction in
            let stories = StoryFinder.storiesForListView(transaction: transaction)
            XCTAssert(stories.isEmpty)
        }
    }

    func testLegacyClientDownloadedButUnviewed() throws {
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
        let cleanupPromise = manager.enqueueOnboardingStoryDownload()
        XCTAssertNotNil(cleanupPromise.value)

        read { transaction in
            if let mockManager = Self.systemStoryManager as? SystemStoryManagerMock {
                mockManager.areSystemStoriesHidden = manager.areSystemStoriesHidden(transaction: transaction)
                mockManager.isOnboardingStoryRead = manager.isOnboardingStoryViewed(transaction: transaction)
            }

            let stories = StoryFinder.unviewedSenderCount(transaction: transaction)
            XCTAssert(stories == 0)
        }
    }

    func testCleanUpViewedStory_notTimedOut() throws {
        mockSignalService.mockUrlSessionBuilder = { _, _, _ in
            let mockSession = MockDownloadSession()
            var dataCount = 0
            mockSession.dataPromiseSource = { url in
                dataCount += 1
                guard dataCount <= 1 else {
                    XCTFail("Downloading more than once")
                    return .init(error: OWSAssertionError(""))
                }
                if
                    let url = url,
                    url.path.hasSuffix(SystemStoryManager.Constants.manifestPath)
                {
                    return .value(HTTPResponseImpl(
                        requestUrl: url,
                        status: 200,
                        headers: .init(),
                        bodyData: Self.manifestJSON
                    ))
                } else {
                    XCTFail("Got invalid download task url")
                    return .init(error: OWSAssertionError(""))
                }
            }
            var downloadCount = 0
            mockSession.downloadPromiseSource = { url in
                downloadCount += 1
                guard downloadCount <= Self.imageNames.count else {
                    XCTFail("Downloading more than once")
                    return .init(error: OWSAssertionError(""))
                }
                if let url = url {
                    XCTAssert(Self.imageNames
                        .map { $0 + SystemStoryManager.Constants.imageExtension }
                        .contains(url.lastPathComponent)
                    )
                    return .value(OWSUrlDownloadResponse(
                        task: URLSessionTask(), // doesn't matter
                        httpUrlResponse: HTTPURLResponse(
                            url: url,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: nil
                        )!,
                        downloadUrl: URL(fileURLWithPath: url.lastPathComponent)
                    ))
                } else {
                    XCTFail("No URL")
                    fatalError()
                }
            }
            return mockSession
        }

        let downloadPromise = manager.enqueueOnboardingStoryDownload()
        XCTAssertNotNil(downloadPromise.value)

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

        let cleanupPromise = manager.cleanUpOnboardingStoryIfNeeded()
        XCTAssertNotNil(cleanupPromise.value)

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

    var dataPromiseSource: ((URL?) -> Promise<HTTPResponse>)?

    override func dataTaskPromise(
        request: URLRequest,
        ignoreAppExpiry: Bool = false
    ) -> Promise<HTTPResponse> {
        guard let dataPromiseSource = dataPromiseSource else {
            fatalError()
        }

        return dataPromiseSource(request.url)
    }

    var downloadPromiseSource: ((URL?) -> Promise<OWSUrlDownloadResponse>)?

    override func downloadTaskPromise(
        request: URLRequest,
        progress progressBlock: BaseOWSURLSessionMock.ProgressBlock?
    ) -> Promise<OWSUrlDownloadResponse> {
        guard let downloadPromiseSource = downloadPromiseSource else {
            fatalError()
        }

        return downloadPromiseSource(request.url)
    }
}
