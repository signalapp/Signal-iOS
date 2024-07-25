//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit
import SignalUI

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
    private var mockDB: MockDB!

    override func setUp() {
        super.setUp()

        mockDB = MockDB()
        mockLinkPreviewManager = MockLinkPreviewManager()
    }

    func testUpdateLoaded() async throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            db: mockDB,
            linkPreviewManager: mockLinkPreviewManager
        )

        // Non-URL text shouldn't issue any fetches.
        for textValue in ["a", "ab", "abc"] {
            await linkPreviewFetcher.update(.init(text: textValue, ranges: .empty))?.value
            XCTAssert(linkPreviewFetcher.currentState.isNone)
            XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
            XCTAssertNil(linkPreviewFetcher.currentUrl)
            XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])
        }

        // A valid URL should fetch only once, even if the text is modified.
        let validURL = try XCTUnwrap(URL(string: "https://signal.org"))
        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            XCTAssertEqual(fetchedURL, validURL)
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Website Title")
        }
        for textValue in ["Check ou https://signal.org", "Check out https://signal.org"] {
            await linkPreviewFetcher.update(.init(text: textValue, ranges: .empty))?.value
            XCTAssert(linkPreviewFetcher.currentState.isLoaded)
            XCTAssertEqual(linkPreviewFetcher.linkPreviewDraftIfLoaded?.url, validURL)
            XCTAssertEqual(linkPreviewFetcher.currentUrl, validURL)
            XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL])
        }

        // An invalid URL should fetch only once, even if the text is modified.
        let invalidURL = try XCTUnwrap(URL(string: "https://signal.org/not_found"))
        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            XCTAssertEqual(fetchedURL, invalidURL)
            throw OWSGenericError("Not found.")
        }
        for textValue in ["Check ou https://signal.org/not_found", "Check out https://signal.org/not_found"] {
            await linkPreviewFetcher.update(.init(text: textValue, ranges: .empty))?.value
            XCTAssert(linkPreviewFetcher.currentState.isFailed)
            XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
            XCTAssertEqual(linkPreviewFetcher.currentUrl, invalidURL)
            XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL, invalidURL])
        }

        // Removing the URL should clear the link preview.
        for textValue in ["Check out", "Check ou"] {
            await linkPreviewFetcher.update(.init(text: textValue, ranges: .empty))?.value
            XCTAssert(linkPreviewFetcher.currentState.isNone)
            XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
            XCTAssertNil(linkPreviewFetcher.currentUrl)
            XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL, invalidURL])
        }
    }

    private struct PendingFetchState {
        var isReady = false
        var deferredBlocks = [() -> Void]()
        var expectedCount: Int

        mutating func resolveIfReady() {
            guard self.isReady, self.deferredBlocks.count == self.expectedCount else {
                return
            }
            self.deferredBlocks.forEach { $0() }
            self.deferredBlocks.removeAll()
        }
    }

    func testUpdateLoading() async throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            db: mockDB,
            linkPreviewManager: mockLinkPreviewManager
        )

        let validURL = try XCTUnwrap(URL(string: "https://signal.org"))
        let pendingFetchState = AtomicValue(PendingFetchState(expectedCount: 1), lock: .init())
        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return try await withCheckedThrowingContinuation { continuation in
                pendingFetchState.update {
                    $0.deferredBlocks.append {
                        continuation.resume(returning: OWSLinkPreviewDraft(url: fetchedURL, title: "Website Title"))
                    }
                    $0.resolveIfReady()
                }
            }
        }

        let task1 = linkPreviewFetcher.update(.init(text: "https://signal.org is a grea", ranges: .empty))
        XCTAssert(linkPreviewFetcher.currentState.isLoading)

        // If there's a request in flight, we shouldn't send a new request.
        let task2 = linkPreviewFetcher.update(.init(text: "https://signal.org is a great", ranges: .empty))
        XCTAssert(linkPreviewFetcher.currentState.isLoading)

        pendingFetchState.update {
            $0.isReady = true
            $0.resolveIfReady()
        }

        await task1?.value
        await task2?.value

        XCTAssert(linkPreviewFetcher.currentState.isLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [validURL])
    }

    func testUpdateObsolete() async throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            db: mockDB,
            linkPreviewManager: mockLinkPreviewManager
        )

        let pendingFetchState = AtomicValue(PendingFetchState(expectedCount: 2), lock: .init())
        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return try await withCheckedThrowingContinuation { continuation in
                pendingFetchState.update {
                    $0.deferredBlocks.append {
                        continuation.resume(returning: OWSLinkPreviewDraft(url: fetchedURL, title: "Website Title"))
                    }
                    $0.resolveIfReady()
                }
            }
        }

        let url1 = try XCTUnwrap(URL(string: "https://signal.org/one"))
        let task1 = linkPreviewFetcher.update(.init(text: "https://signal.org/one", ranges: .empty))
        XCTAssert(linkPreviewFetcher.currentState.isLoading)

        // If there's a request in flight & we change the URL, drop the original request.
        let url2 = try XCTUnwrap(URL(string: "https://signal.org/two"))
        let task2 = linkPreviewFetcher.update(.init(text: "https://signal.org/two", ranges: .empty))
        XCTAssert(linkPreviewFetcher.currentState.isLoading)

        pendingFetchState.update {
            $0.isReady = true
            $0.resolveIfReady()
        }

        await task1?.value
        await task2?.value

        XCTAssert(linkPreviewFetcher.currentState.isLoaded)
        XCTAssertEqual(linkPreviewFetcher.linkPreviewDraftIfLoaded?.url, url2)
        XCTAssertEqual(linkPreviewFetcher.currentUrl, url2)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [url1, url2])
    }

    func testUpdatePrependScheme() async throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            db: mockDB,
            linkPreviewManager: mockLinkPreviewManager
        )

        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Signal")
        }
        await linkPreviewFetcher.update(.init(text: "signal.org", ranges: .empty), prependSchemeIfNeeded: false)?.value
        XCTAssert(linkPreviewFetcher.currentState.isNone)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // If we should prepend a scheme, prepend "https://".
        await linkPreviewFetcher.update(.init(text: "signal.org", ranges: .empty), prependSchemeIfNeeded: true)?.value
        XCTAssert(linkPreviewFetcher.currentState.isLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [URL(string: "https://signal.org")!])
        mockLinkPreviewManager.fetchedURLs.removeAll()

        // If there's already a scheme, we don't add "https://". (We require
        // "https://", so specify anything other scheme disables link previews.
        await linkPreviewFetcher.update(.init(text: "http://signal.org", ranges: .empty), prependSchemeIfNeeded: true)?.value
        XCTAssert(linkPreviewFetcher.currentState.isNone)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])
    }

    func testOnStateChange() async throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            db: mockDB,
            linkPreviewManager: mockLinkPreviewManager
        )

        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Signal")
        }

        var onStateChangeCount = 0
        linkPreviewFetcher.onStateChange = { onStateChangeCount += 1 }

        await linkPreviewFetcher.update(.init(text: "", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 0)

        // Redundant updates generally don't result in state updates.
        await linkPreviewFetcher.update(.init(text: "a", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 0)

        // Fetching a URL should update the state twice: to loading & to loaded.
        await linkPreviewFetcher.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 2)

        await linkPreviewFetcher.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 2)

        // Clearing the text should update the link preview.
        await linkPreviewFetcher.update(.init(text: "", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 3)

        // Assigning the URL again should fetch it again.
        await linkPreviewFetcher.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 5)

        // Disabling the link preview should trigger an update.
        linkPreviewFetcher.disable()
        XCTAssertEqual(onStateChangeCount, 6)
    }

    func testDisable() async throws {
        let linkPreviewFetcher = LinkPreviewFetcher(
            db: mockDB,
            linkPreviewManager: mockLinkPreviewManager
        )

        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Signal")
        }

        // Fetch the original preview.
        let url = try XCTUnwrap(URL(string: "https://signal.org"))
        await linkPreviewFetcher.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertEqual(linkPreviewFetcher.linkPreviewDraftIfLoaded?.url, url)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [url])
        mockLinkPreviewManager.fetchedURLs.removeAll()

        // Dismiss the preview; make sure it goes away.
        linkPreviewFetcher.disable()
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Assign the same URL again; make sure it doesn't come back.
        await linkPreviewFetcher.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Clear the URL; make sure it stays away.
        await linkPreviewFetcher.update(.init(text: "", ranges: .empty))?.value
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Enter a different URL; make sure we don't fetch it.
        await linkPreviewFetcher.update(.init(text: "https://signal.org/one", ranges: .empty))?.value
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Ensure "enableIfEmpty" doesn't enable when the text isn't empty.
        await linkPreviewFetcher.update(.init(text: "https://signal.org/one", ranges: .empty), enableIfEmpty: true)?.value
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Clear the text with "enableIfEmpty" to re-enable link previews.
        await linkPreviewFetcher.update(.init(text: "", ranges: .empty), enableIfEmpty: true)?.value
        XCTAssertNil(linkPreviewFetcher.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [])

        // Set a URL and make sure we fetch it.
        let url2 = try XCTUnwrap(URL(string: "https://signal.org/two"))
        await linkPreviewFetcher.update(.init(text: "https://signal.org/two", ranges: .empty), enableIfEmpty: true)?.value
        XCTAssertEqual(linkPreviewFetcher.linkPreviewDraftIfLoaded?.url, url2)
        XCTAssertEqual(mockLinkPreviewManager.fetchedURLs, [url2])
    }

    func testOnlyParseIfEnabled() async throws {
        mockLinkPreviewManager.areLinkPreviewsEnabledMock = false

        do {
            let linkPreviewFetcher = LinkPreviewFetcher(
                db: mockDB,
                linkPreviewManager: mockLinkPreviewManager,
                onlyParseIfEnabled: true
            )

            await linkPreviewFetcher.update(.init(text: "https://signal.org", ranges: .empty))?.value
            XCTAssertNil(linkPreviewFetcher.currentUrl)
        }
        do {
            let linkPreviewFetcher = LinkPreviewFetcher(
                db: mockDB,
                linkPreviewManager: mockLinkPreviewManager,
                onlyParseIfEnabled: false
            )

            // If link previews are disabled, we may still want to parse URLs in the
            // text so that they can be attached (without a preview) to text stories.
            mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
                throw OWSGenericError("Not found.")
            }
            await linkPreviewFetcher.update(.init(text: "https://signal.org", ranges: .empty))?.value
            XCTAssertEqual(linkPreviewFetcher.currentUrl, try XCTUnwrap(URL(string: "https://signal.org")))
        }
    }

    func testDontParseInSpoilers() async throws {
        mockLinkPreviewManager.fetchLinkPreviewBlock = { fetchedURL in
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Signal")
        }

        let linkPreviewFetcher = LinkPreviewFetcher(
            db: mockDB,
            linkPreviewManager: mockLinkPreviewManager,
            onlyParseIfEnabled: true
        )

        // Bold should have no effect
        await linkPreviewFetcher.update(.init(
            text: "https://signal.org",
            ranges: .init(
                mentions: [:],
                styles: [.init(.bold, range: NSRange(location: 0, length: 18))]
            )
        ))?.value
        XCTAssertNotNil(linkPreviewFetcher.currentUrl)

        // Spoiler should mean we don't match.
        await linkPreviewFetcher.update(.init(
            text: "https://signal.org",
            ranges: .init(
                mentions: [:],
                styles: [.init(.spoiler, range: NSRange(location: 0, length: 18))]
            )
        ))?.value
        XCTAssertNil(linkPreviewFetcher.currentUrl)

        // Even if only partially covering.
        await linkPreviewFetcher.update(.init(
            text: "https://signal.org",
            ranges: .init(
                mentions: [:],
                styles: [.init(.spoiler, range: NSRange(location: 3, length: 5))]
            )
        ))?.value
        XCTAssertNil(linkPreviewFetcher.currentUrl)

        // Including if we prepend a prefix.
        await linkPreviewFetcher.update(.init(
            text: "signal.org",
            ranges: .init(
                mentions: [:],
                styles: [.init(.spoiler, range: NSRange(location: 5, length: 5))]
            )
        ))?.value
        XCTAssertNil(linkPreviewFetcher.currentUrl)
    }
}
