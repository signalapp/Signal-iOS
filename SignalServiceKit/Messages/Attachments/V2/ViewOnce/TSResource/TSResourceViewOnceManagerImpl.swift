//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceViewOnceManagerImpl: TSResourceViewOnceManager {

    private let attachmentViewOnceManager: AttachmentViewOnceManager
    private let db: any DB

    public init(
        attachmentViewOnceManager: AttachmentViewOnceManager,
        db: any DB
    ) {
        self.attachmentViewOnceManager = attachmentViewOnceManager
        self.db = db
    }

    public func prepareViewOnceContentForDisplay(_ message: TSMessage) -> TSViewOnceContent? {
        return attachmentViewOnceManager.prepareViewOnceContentForDisplay(message)?.asTSContent
    }
}
