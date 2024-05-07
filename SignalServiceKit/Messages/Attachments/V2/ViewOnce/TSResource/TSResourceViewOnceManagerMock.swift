//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class TSResourceViewOnceManagerMock: TSResourceViewOnceManager {

    public init() {}

    open func prepareViewOnceContentForDisplay(_ message: TSMessage) -> TSViewOnceContent? {
        return nil
    }
}

#endif
