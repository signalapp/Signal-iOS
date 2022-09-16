//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit

class SystemStoryManagerTest: SSKBaseTestSwift {

    let timeout: TimeInterval = 5

    var mockSignalService: OWSSignalServiceMock {
        return signalService as! OWSSignalServiceMock
    }

    var manager: SystemStoryManager!

    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: "+17875550101", uuid: UUID(), pni: UUID())
        manager = SystemStoryManager(fileSystem: OnboardingStoryManagerFilesystemMock.self)
    }

    // MARK: - Downloading

    func testDownloadStory() throws {
        mockSignalService.mockUrlSessionBuilder = { _ in
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
                    XCTFail()
                    fatalError()
                }
            }
            return mockSession
        }

        let expectation = self.expectation(description: "promise fulfillment")
        let downloadPromise = manager.enqueueOnboardingStoryDownload()

        downloadPromise.observe { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Error when downloading: \(error)")
            }
            expectation.fulfill()
        }
        self.waitForExpectations(timeout: timeout)
    }

    func testDownloadStory_multipleTimes() throws {
        mockSignalService.mockUrlSessionBuilder = { _ in
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
                    XCTFail()
                    fatalError()
                }
            }
            return mockSession
        }

        let firstExpectation = self.expectation(description: "1st promise")
        let firstDownloadPromise = manager.enqueueOnboardingStoryDownload()

        // before the first can fulfill, start a second
        let secondExpectation = self.expectation(description: "2nd promise")
        let secondDownloadPromise = manager.enqueueOnboardingStoryDownload()

        firstDownloadPromise.observe { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Error when downloading: \(error)")
            }
            firstExpectation.fulfill()
        }
        secondDownloadPromise.observe { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Error when downloading: \(error)")
            }
            secondExpectation.fulfill()
        }
        self.waitForExpectations(timeout: timeout)

        // After we've fulfilled, try again, which should't redownload.

        mockSignalService.mockUrlSessionBuilder = { _ in
            XCTFail("Should not be issuing another network request.")
            return .init()
        }

        let thirdExpectation = self.expectation(description: "3rd promise")
        let thirdDownloadPromise = manager.enqueueOnboardingStoryDownload()

        thirdDownloadPromise.observe { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Error when downloading: \(error)")
            }
            thirdExpectation.fulfill()
        }
        self.waitForExpectations(timeout: timeout)
    }

    // MARK: - Viewed state

    func testCleanUpViewedStory() throws {
        mockSignalService.mockUrlSessionBuilder = { _ in
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
                    XCTFail()
                    fatalError()
                }
            }
            return mockSession
        }

        let downloadExpectation = self.expectation(description: "download promise")
        let downloadPromise = manager.enqueueOnboardingStoryDownload()

        downloadPromise.observe { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Error when downloading: \(error)")
            }
            downloadExpectation.fulfill()
        }
        self.waitForExpectations(timeout: timeout)

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

        let cleanupExpectation = self.expectation(description: "cleanup")
        let cleanupPromise = manager.cleanUpOnboardingStoryIfNeeded()

        cleanupPromise.observe { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Error when cleaning up: \(error)")
            }
            cleanupExpectation.fulfill()
        }
        self.wait(for: [cleanupExpectation], timeout: timeout)

        // Check that stories were indeed deleted.
        read { transaction in
            let stories = StoryFinder.storiesForListView(transaction: transaction)
            XCTAssert(stories.isEmpty)
        }
    }

    #if BROKEN_TESTS

    func testCleanUpViewedStory_notTimedOut() throws {
        mockSignalService.mockUrlSessionBuilder = { _ in
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
                    XCTFail()
                    fatalError()
                }
            }
            return mockSession
        }

        let downloadExpectation = self.expectation(description: "download promise")
        let downloadPromise = manager.enqueueOnboardingStoryDownload()

        downloadPromise.observe { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Error when downloading: \(error)")
            }
            downloadExpectation.fulfill()
        }
        self.waitForExpectations(timeout: timeout)

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

        let cleanupExpectation = self.expectation(description: "cleanup")
        let cleanupPromise = manager.cleanUpOnboardingStoryIfNeeded()

        cleanupPromise.observe { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTFail("Error when cleaning up: \(error)")
            }
            cleanupExpectation.fulfill()
        }
        self.wait(for: [cleanupExpectation], timeout: timeout)

        // Check that stories were not deleted.
        read { transaction in
            let stories = StoryFinder.storiesForListView(transaction: transaction)
            XCTAssertEqual(stories.count, Self.imageNames.count)
        }
    }

    #endif

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

private class MockDownloadSession: OWSURLSessionMock {

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
        progress progressBlock: OWSURLSessionMock.ProgressBlock?
    ) -> Promise<OWSUrlDownloadResponse> {
        guard let downloadPromiseSource = downloadPromiseSource else {
            fatalError()
        }

        return downloadPromiseSource(request.url)
    }
}
