//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalCoreKit
import SignalServiceKit
import SignalUI

private class MockLinkPreviewManager: LinkPreviewManager {
    var areLinkPreviewsEnabledWithSneakyTransaction = true

    var fetchedURLs = [URL]()

    var fetchLinkPreviewBlock: ((URL) -> Promise<OWSLinkPreviewDraft>)?

    func fetchLinkPreview(for url: URL) -> Promise<OWSLinkPreviewDraft> {
        fetchedURLs.append(url)
        return fetchLinkPreviewBlock!(url)
    }
}

private extension LinkPreviewFetcher.State {
    var isNone: Bool {
        if case .none = self {
            return true
        }
        return false
    }
    var isLoaded: Bool {
        if case .loaded = self {
            return true
        }
        return false
    }
    var isFailed: Bool {
        if case .failed = self {
            return true
        }
        return false
    }
    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }
}

class LinkPreviewFetcherTest: XCTestCase {

    private var mockLinkPreviewManager: MockLinkPreviewManager!
    private var testScheduler: TestScheduler!

    override func setUp() {
        super.setUp()

        mockLinkPreviewManager = MockLinkPreviewManager()
        testScheduler = TestScheduler()
        testScheduler.start()
    }

    func testUpdateLoaded() throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            linkPreviewManager: mockLinkPreviewManager,
            schedulers: TestSchedulers(scheduler: testScheduler)
        )

        // Non-URL text shouldn't issue any fetches.
        for textValue in ["a", "ab", "abc"] {
            linkPreviewFetcher.update(textValue)
            XCTAssert(linkPreviewFetcher.currentState.isNone)
            XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
            XCTAssertNil(linkPreviewFetcher.currentUrl)
            XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])
        }

        // A valid URL should fetch only once, even if the text is modified.
        let validURL = try XCTUnwrap(URL(string: "https://signal.org"))
        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            XCTAssertEqual(fetchedURL, validURL)
            return .value(OWSLinkPreviewDraft(url: fetchedURL, title: "Website Title"))
        }
        for textValue in ["Check ou https://signal.org", "Check out https://signal.org"] {
            linkPreviewFetcher.update(textValue)
            XCTAssert(linkPreviewFetcher.currentState.isLoaded)
            XCTAssertEqual(linkPreviewFetcher.linkPreviewDraftIfLoaded?.url, validURL)
            XCTAssertEqual(linkPreviewFetcher.currentUrl, validURL)
            XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL])
        }

        // An invalid URL should fetch only once, even if the text is modified.
        let invalidURL = try XCTUnwrap(URL(string: "https://signal.org/not_found"))
        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            XCTAssertEqual(fetchedURL, invalidURL)
            return Promise(error: OWSGenericError("Not found."))
        }
        for textValue in ["Check ou https://signal.org/not_found", "Check out https://signal.org/not_found"] {
            linkPreviewFetcher.update(textValue)
            XCTAssert(linkPreviewFetcher.currentState.isFailed)
            XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
            XCTAssertEqual(linkPreviewFetcher.currentUrl, invalidURL)
            XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL, invalidURL])
        }

        // Removing the URL should clear the link preview.
        for textValue in ["Check out", "Check ou"] {
            linkPreviewFetcher.update(textValue)
            XCTAssert(linkPreviewFetcher.currentState.isNone)
            XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
            XCTAssertNil(linkPreviewFetcher.currentUrl)
            XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL, invalidURL])
        }
    }

    func testUpdateLoading() throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            linkPreviewManager: mockLinkPreviewManager,
            schedulers: TestSchedulers(scheduler: testScheduler)
        )

        let validURL = try XCTUnwrap(URL(string: "https://signal.org"))
        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return .value(OWSLinkPreviewDraft(url: fetchedURL, title: "Website Title"))
        }

        testScheduler.stop()

        linkPreviewFetcher.update("https://signal.org is a grea")
        XCTAssert(linkPreviewFetcher.currentState.isLoading)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL])

        // If there's a request in flight, we shouldn't send a new request.
        linkPreviewFetcher.update("https://signal.org is a great")
        XCTAssert(linkPreviewFetcher.currentState.isLoading)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL])

        testScheduler.start()

        XCTAssert(linkPreviewFetcher.currentState.isLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL])
    }

    func testUpdateObsolete() throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            linkPreviewManager: mockLinkPreviewManager,
            schedulers: TestSchedulers(scheduler: testScheduler)
        )

        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return .value(OWSLinkPreviewDraft(url: fetchedURL, title: "Website Title"))
        }

        testScheduler.stop()

        let url1 = try XCTUnwrap(URL(string: "https://signal.org/one"))
        linkPreviewFetcher.update("https://signal.org/one")
        XCTAssert(linkPreviewFetcher.currentState.isLoading)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [url1])

        // If there's a request in flight & we change the URL, drop the original request.
        let url2 = try XCTUnwrap(URL(string: "https://signal.org/two"))
        linkPreviewFetcher.update("https://signal.org/two")
        XCTAssert(linkPreviewFetcher.currentState.isLoading)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [url1, url2])

        testScheduler.start()

        XCTAssert(linkPreviewFetcher.currentState.isLoaded)
        XCTAssertEqual(linkPreviewFetcher.linkPreviewDraftIfLoaded?.url, url2)
        XCTAssertEqual(linkPreviewFetcher.currentUrl, url2)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [url1, url2])
    }

    func testUpdatePrependScheme() {
        let linkPreviewFetcher = LinkPreviewFetcher(
            linkPreviewManager: mockLinkPreviewManager,
            schedulers: TestSchedulers(scheduler: testScheduler)
        )

        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return .value(OWSLinkPreviewDraft(url: fetchedURL, title: "Signal"))
        }
        linkPreviewFetcher.update("signal.org", prependSchemeIfNeeded: false)
        XCTAssert(linkPreviewFetcher.currentState.isNone)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // If we should prepend a scheme, prepend "https://".
        linkPreviewFetcher.update("signal.org", prependSchemeIfNeeded: true)
        XCTAssert(linkPreviewFetcher.currentState.isLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [URL(string: "https://signal.org")!])
        mockLinkPreviewManager.fetchedURLs.removeAll()

        // If there's already a scheme, we don't add "https://". (We require
        // "https://", so specify anything other scheme disables link previews.
        linkPreviewFetcher.update("http://signal.org", prependSchemeIfNeeded: true)
        XCTAssert(linkPreviewFetcher.currentState.isNone)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])
    }

    func testOnStateChange() throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            linkPreviewManager: mockLinkPreviewManager,
            schedulers: TestSchedulers(scheduler: testScheduler)
        )

        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return .value(OWSLinkPreviewDraft(url: fetchedURL, title: "Signal"))
        }

        var onStateChangeCount = 0
        linkPreviewFetcher.onStateChange = { onStateChangeCount += 1 }

        linkPreviewFetcher.update("")
        XCTAssertEqual(onStateChangeCount, 0)

        // Redundant updates generally don't result in state updates.
        linkPreviewFetcher.update("a")
        XCTAssertEqual(onStateChangeCount, 0)

        // Fetching a URL should update the state twice: to loading & to loaded.
        linkPreviewFetcher.update("https://signal.org")
        XCTAssertEqual(onStateChangeCount, 2)

        linkPreviewFetcher.update("https://signal.org")
        XCTAssertEqual(onStateChangeCount, 2)

        // Clearing the text should update the link preview.
        linkPreviewFetcher.update("")
        XCTAssertEqual(onStateChangeCount, 3)

        // Assigning the URL again should fetch it again.
        linkPreviewFetcher.update("https://signal.org")
        XCTAssertEqual(onStateChangeCount, 5)

        // Disabling the link preview should trigger an update.
        linkPreviewFetcher.disable()
        XCTAssertEqual(onStateChangeCount, 6)
    }

    func testDisable() throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            linkPreviewManager: mockLinkPreviewManager,
            schedulers: TestSchedulers(scheduler: testScheduler)
        )

        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return .value(OWSLinkPreviewDraft(url: fetchedURL, title: "Signal"))
        }

        // Fetch the original preview.
        let url = try XCTUnwrap(URL(string: "https://signal.org"))
        linkPreviewFetcher.update("https://signal.org")
        XCTAssertEqual(linkPreviewFetcher.linkPreviewDraftIfLoaded?.url, url)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [url])
        mockLinkPreviewManager.fetchedURLs.removeAll()

        // Dismiss the preview; make sure it goes away.
        linkPreviewFetcher.disable()
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Assign the same URL again; make sure it doesn't come back.
        linkPreviewFetcher.update("https://signal.org")
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Clear the URL; make sure it stays away.
        linkPreviewFetcher.update("")
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Enter a different URL; make sure we don't fetch it.
        linkPreviewFetcher.update("https://signal.org/one")
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Ensure "enableIfEmpty" doesn't enable when the text isn't empty.
        linkPreviewFetcher.update("https://signal.org/one", enableIfEmpty: true)
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Clear the text with "enableIfEmpty" to re-enable link previews.
        linkPreviewFetcher.update("", enableIfEmpty: true)
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Set a URL and make sure we fetch it.
        let url2 = try XCTUnwrap(URL(string: "https://signal.org/two"))
        linkPreviewFetcher.update("https://signal.org/two", enableIfEmpty: true)
        XCTAssertEqual(linkPreviewFetcher.linkPreviewDraftIfLoaded?.url, url2)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [url2])
    }

    func testOnlyParseIfEnabled() throws {
        mockLinkPreviewManager.areLinkPreviewsEnabledWithSneakyTransaction = false

        do {
            let linkPreviewFetcher = LinkPreviewFetcher(
                linkPreviewManager: mockLinkPreviewManager,
                schedulers: TestSchedulers(scheduler: testScheduler),
                onlyParseIfEnabled: true
            )

            linkPreviewFetcher.update("https://signal.org")
            XCTAssertNil(linkPreviewFetcher.currentUrl)
        }
        do {
            let linkPreviewFetcher = LinkPreviewFetcher(
                linkPreviewManager: mockLinkPreviewManager,
                schedulers: TestSchedulers(scheduler: testScheduler),
                onlyParseIfEnabled: false
            )

            // If link previews are disabled, we may still want to parse URLs in the
            // text so that they can be attached (without a preview) to text stories.
            mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
                return Promise(error: OWSGenericError("Not found."))
            }
            linkPreviewFetcher.update("https://signal.org")
            XCTAssertEqual(linkPreviewFetcher.currentUrl, try XCTUnwrap(URL(string: "https://signal.org")))
        }
    }
}
