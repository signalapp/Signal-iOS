//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol LinkPreviewManager {

    func areLinkPreviewsEnabled(tx: DBReadTransaction) -> Bool

    func fetchLinkPreview(for url: URL) -> Promise<OWSLinkPreviewDraft>
}
