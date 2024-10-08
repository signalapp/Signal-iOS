//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
@testable import SignalUI

private extension LinkPreviewFetchState.State {
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

class LinkPreviewFetchStateTest: XCTestCase {

    private var mockLinkPreviewFetcher: MockLinkPreviewFetcher!
    private var mockDB: InMemoryDB!

    override func setUp() {
        super.setUp()

        mockDB = InMemoryDB()
        mockLinkPreviewFetcher = MockLinkPreviewFetcher()
    }

    private func linkPreviewFetchState(
        areLinkPreviewsEnabled: Bool = true,
        onlyParseIfEnabled: Bool = false
    ) -> LinkPreviewFetchState {
        let linkPreviewSettingStore = LinkPreviewSettingStore.mock()
        mockDB.write { tx in
            linkPreviewSettingStore.setAreLinkPreviewsEnabled(areLinkPreviewsEnabled, tx: tx)
        }
        return LinkPreviewFetchState(
            db: mockDB,
            linkPreviewFetcher: mockLinkPreviewFetcher,
            linkPreviewSettingStore: linkPreviewSettingStore,
            onlyParseIfEnabled: onlyParseIfEnabled,
            linkPreviewDraft: nil
        )
    }

    func testUpdateLoaded() async throws {
        let linkPreviewFetchState = self.linkPreviewFetchState()

        // Non-URL text shouldn't issue any fetches.
        for textValue in ["a", "ab", "abc"] {
            await linkPreviewFetchState.update(.init(text: textValue, ranges: .empty))?.value
            XCTAssert(linkPreviewFetchState.currentState.isNone)
            XCTAssertNil(linkPreviewFetchState.linkPreviewDraftIfLoaded)
            XCTAssertNil(linkPreviewFetchState.currentUrl)
            XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [])
        }

        // A valid URL should fetch only once, even if the text is modified.
        let validURL = try XCTUnwrap(URL(string: "https://signal.org"))
        mockLinkPreviewFetcher.fetchLinkPreviewBlock = { fetchedURL in
            XCTAssertEqual(fetchedURL, validURL)
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Website Title")
        }
        for textValue in ["Check ou https://signal.org", "Check out https://signal.org"] {
            await linkPreviewFetchState.update(.init(text: textValue, ranges: .empty))?.value
            XCTAssert(linkPreviewFetchState.currentState.isLoaded)
            XCTAssertEqual(linkPreviewFetchState.linkPreviewDraftIfLoaded?.url, validURL)
            XCTAssertEqual(linkPreviewFetchState.currentUrl, validURL)
            XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [validURL])
        }

        // An invalid URL should fetch only once, even if the text is modified.
        let invalidURL = try XCTUnwrap(URL(string: "https://signal.org/not_found"))
        mockLinkPreviewFetcher.fetchLinkPreviewBlock = { fetchedURL in
            XCTAssertEqual(fetchedURL, invalidURL)
            throw OWSGenericError("Not found.")
        }
        for textValue in ["Check ou https://signal.org/not_found", "Check out https://signal.org/not_found"] {
            await linkPreviewFetchState.update(.init(text: textValue, ranges: .empty))?.value
            XCTAssert(linkPreviewFetchState.currentState.isFailed)
            XCTAssertNil(linkPreviewFetchState.linkPreviewDraftIfLoaded)
            XCTAssertEqual(linkPreviewFetchState.currentUrl, invalidURL)
            XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [validURL, invalidURL])
        }

        // Removing the URL should clear the link preview.
        for textValue in ["Check out", "Check ou"] {
            await linkPreviewFetchState.update(.init(text: textValue, ranges: .empty))?.value
            XCTAssert(linkPreviewFetchState.currentState.isNone)
            XCTAssertNil(linkPreviewFetchState.linkPreviewDraftIfLoaded)
            XCTAssertNil(linkPreviewFetchState.currentUrl)
            XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [validURL, invalidURL])
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
        let linkPreviewFetchState = self.linkPreviewFetchState()

        let validURL = try XCTUnwrap(URL(string: "https://signal.org"))
        let pendingFetchState = AtomicValue(PendingFetchState(expectedCount: 1), lock: .init())
        mockLinkPreviewFetcher.fetchLinkPreviewBlock = { fetchedURL in
            return try await withCheckedThrowingContinuation { continuation in
                pendingFetchState.update {
                    $0.deferredBlocks.append {
                        continuation.resume(returning: OWSLinkPreviewDraft(url: fetchedURL, title: "Website Title"))
                    }
                    $0.resolveIfReady()
                }
            }
        }

        let task1 = linkPreviewFetchState.update(.init(text: "https://signal.org is a grea", ranges: .empty))
        XCTAssert(linkPreviewFetchState.currentState.isLoading)

        // If there's a request in flight, we shouldn't send a new request.
        let task2 = linkPreviewFetchState.update(.init(text: "https://signal.org is a great", ranges: .empty))
        XCTAssert(linkPreviewFetchState.currentState.isLoading)

        pendingFetchState.update {
            $0.isReady = true
            $0.resolveIfReady()
        }

        await task1?.value
        await task2?.value

        XCTAssert(linkPreviewFetchState.currentState.isLoaded)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [validURL])
    }

    func testUpdateObsolete() async throws {
        let linkPreviewFetchState = self.linkPreviewFetchState()

        let pendingFetchState = AtomicValue(PendingFetchState(expectedCount: 2), lock: .init())
        mockLinkPreviewFetcher.fetchLinkPreviewBlock = { fetchedURL in
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
        let task1 = linkPreviewFetchState.update(.init(text: "https://signal.org/one", ranges: .empty))
        XCTAssert(linkPreviewFetchState.currentState.isLoading)

        // If there's a request in flight & we change the URL, drop the original request.
        let url2 = try XCTUnwrap(URL(string: "https://signal.org/two"))
        let task2 = linkPreviewFetchState.update(.init(text: "https://signal.org/two", ranges: .empty))
        XCTAssert(linkPreviewFetchState.currentState.isLoading)

        pendingFetchState.update {
            $0.isReady = true
            $0.resolveIfReady()
        }

        await task1?.value
        await task2?.value

        XCTAssert(linkPreviewFetchState.currentState.isLoaded)
        XCTAssertEqual(linkPreviewFetchState.linkPreviewDraftIfLoaded?.url, url2)
        XCTAssertEqual(linkPreviewFetchState.currentUrl, url2)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [url1, url2])
    }

    func testUpdatePrependScheme() async throws {
        let linkPreviewFetchState = self.linkPreviewFetchState()

        mockLinkPreviewFetcher.fetchLinkPreviewBlock = { fetchedURL in
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Signal")
        }
        await linkPreviewFetchState.update(.init(text: "signal.org", ranges: .empty), prependSchemeIfNeeded: false)?.value
        XCTAssert(linkPreviewFetchState.currentState.isNone)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [])

        // If we should prepend a scheme, prepend "https://".
        await linkPreviewFetchState.update(.init(text: "signal.org", ranges: .empty), prependSchemeIfNeeded: true)?.value
        XCTAssert(linkPreviewFetchState.currentState.isLoaded)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [URL(string: "https://signal.org")!])
        mockLinkPreviewFetcher.fetchedURLs.removeAll()

        // If there's already a scheme, we don't add "https://". (We require
        // "https://", so specify anything other scheme disables link previews.
        await linkPreviewFetchState.update(.init(text: "http://signal.org", ranges: .empty), prependSchemeIfNeeded: true)?.value
        XCTAssert(linkPreviewFetchState.currentState.isNone)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [])
    }

    func testOnStateChange() async throws {
        let linkPreviewFetchState = self.linkPreviewFetchState()

        mockLinkPreviewFetcher.fetchLinkPreviewBlock = { fetchedURL in
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Signal")
        }

        var onStateChangeCount = 0
        linkPreviewFetchState.onStateChange = { onStateChangeCount += 1 }

        await linkPreviewFetchState.update(.init(text: "", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 0)

        // Redundant updates generally don't result in state updates.
        await linkPreviewFetchState.update(.init(text: "a", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 0)

        // Fetching a URL should update the state twice: to loading & to loaded.
        await linkPreviewFetchState.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 2)

        await linkPreviewFetchState.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 2)

        // Clearing the text should update the link preview.
        await linkPreviewFetchState.update(.init(text: "", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 3)

        // Assigning the URL again should fetch it again.
        await linkPreviewFetchState.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertEqual(onStateChangeCount, 5)

        // Disabling the link preview should trigger an update.
        linkPreviewFetchState.disable()
        XCTAssertEqual(onStateChangeCount, 6)
    }

    func testDisable() async throws {
        let linkPreviewFetchState = self.linkPreviewFetchState()

        mockLinkPreviewFetcher.fetchLinkPreviewBlock = { fetchedURL in
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Signal")
        }

        // Fetch the original preview.
        let url = try XCTUnwrap(URL(string: "https://signal.org"))
        await linkPreviewFetchState.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertEqual(linkPreviewFetchState.linkPreviewDraftIfLoaded?.url, url)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [url])
        mockLinkPreviewFetcher.fetchedURLs.removeAll()

        // Dismiss the preview; make sure it goes away.
        linkPreviewFetchState.disable()
        XCTAssertNil(linkPreviewFetchState.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [])

        // Assign the same URL again; make sure it doesn't come back.
        await linkPreviewFetchState.update(.init(text: "https://signal.org", ranges: .empty))?.value
        XCTAssertNil(linkPreviewFetchState.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [])

        // Clear the URL; make sure it stays away.
        await linkPreviewFetchState.update(.init(text: "", ranges: .empty))?.value
        XCTAssertNil(linkPreviewFetchState.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [])

        // Enter a different URL; make sure we don't fetch it.
        await linkPreviewFetchState.update(.init(text: "https://signal.org/one", ranges: .empty))?.value
        XCTAssertNil(linkPreviewFetchState.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [])

        // Ensure "enableIfEmpty" doesn't enable when the text isn't empty.
        await linkPreviewFetchState.update(.init(text: "https://signal.org/one", ranges: .empty), enableIfEmpty: true)?.value
        XCTAssertNil(linkPreviewFetchState.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [])

        // Clear the text with "enableIfEmpty" to re-enable link previews.
        await linkPreviewFetchState.update(.init(text: "", ranges: .empty), enableIfEmpty: true)?.value
        XCTAssertNil(linkPreviewFetchState.linkPreviewDraftIfLoaded)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [])

        // Set a URL and make sure we fetch it.
        let url2 = try XCTUnwrap(URL(string: "https://signal.org/two"))
        await linkPreviewFetchState.update(.init(text: "https://signal.org/two", ranges: .empty), enableIfEmpty: true)?.value
        XCTAssertEqual(linkPreviewFetchState.linkPreviewDraftIfLoaded?.url, url2)
        XCTAssertEqual(mockLinkPreviewFetcher.fetchedURLs, [url2])
    }

    func testOnlyParseIfEnabled() async throws {
        do {
            let linkPreviewFetchState = self.linkPreviewFetchState(
                areLinkPreviewsEnabled: false,
                onlyParseIfEnabled: true
            )

            await linkPreviewFetchState.update(.init(text: "https://signal.org", ranges: .empty))?.value
            XCTAssertNil(linkPreviewFetchState.currentUrl)
        }
        do {
            let linkPreviewFetchState = self.linkPreviewFetchState(
                areLinkPreviewsEnabled: false,
                onlyParseIfEnabled: false
            )

            // If link previews are disabled, we may still want to parse URLs in the
            // text so that they can be attached (without a preview) to text stories.
            mockLinkPreviewFetcher.fetchLinkPreviewBlock = { fetchedURL in
                throw OWSGenericError("Not found.")
            }
            await linkPreviewFetchState.update(.init(text: "https://signal.org", ranges: .empty))?.value
            XCTAssertEqual(linkPreviewFetchState.currentUrl, try XCTUnwrap(URL(string: "https://signal.org")))
        }
    }

    func testDontParseInSpoilers() async throws {
        mockLinkPreviewFetcher.fetchLinkPreviewBlock = { fetchedURL in
            return OWSLinkPreviewDraft(url: fetchedURL, title: "Signal")
        }

        let linkPreviewFetchState = self.linkPreviewFetchState(
            onlyParseIfEnabled: true
        )

        // Bold should have no effect
        await linkPreviewFetchState.update(.init(
            text: "https://signal.org",
            ranges: .init(
                mentions: [:],
                styles: [.init(.bold, range: NSRange(location: 0, length: 18))]
            )
        ))?.value
        XCTAssertNotNil(linkPreviewFetchState.currentUrl)

        // Spoiler should mean we don't match.
        await linkPreviewFetchState.update(.init(
            text: "https://signal.org",
            ranges: .init(
                mentions: [:],
                styles: [.init(.spoiler, range: NSRange(location: 0, length: 18))]
            )
        ))?.value
        XCTAssertNil(linkPreviewFetchState.currentUrl)

        // Even if only partially covering.
        await linkPreviewFetchState.update(.init(
            text: "https://signal.org",
            ranges: .init(
                mentions: [:],
                styles: [.init(.spoiler, range: NSRange(location: 3, length: 5))]
            )
        ))?.value
        XCTAssertNil(linkPreviewFetchState.currentUrl)

        // Including if we prepend a prefix.
        await linkPreviewFetchState.update(.init(
            text: "signal.org",
            ranges: .init(
                mentions: [:],
                styles: [.init(.spoiler, range: NSRange(location: 5, length: 5))]
            )
        ))?.value
        XCTAssertNil(linkPreviewFetchState.currentUrl)
    }
}
