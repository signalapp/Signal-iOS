//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class MockLinkPreviewManager: LinkPreviewManager {

    public init() {}

    public var areLinkPreviewsEnabledMock = true

    public func areLinkPreviewsEnabled(tx: DBReadTransaction) -> Bool {
        return areLinkPreviewsEnabledMock
    }

    public var fetchedURLs = [URL]()

    public var fetchLinkPreviewBlock: ((URL) -> Promise<OWSLinkPreviewDraft>)?

    public func fetchLinkPreview(for url: URL) -> Promise<OWSLinkPreviewDraft> {
        fetchedURLs.append(url)
        return fetchLinkPreviewBlock!(url)
    }
}

#endif
