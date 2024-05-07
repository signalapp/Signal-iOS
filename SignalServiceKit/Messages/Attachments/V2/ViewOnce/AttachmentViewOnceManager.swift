//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AttachmentViewOnceManager {

    /// When presenting a view-once message, we:
    /// 1. copy the displayable attachment contents to a tmp file
    /// 2. delete the original attachment
    /// 3. display the copied contents
    ///
    /// This does steps 1 and 2 and returns displayable contents safely.
    func prepareViewOnceContentForDisplay(_ message: TSMessage) -> ViewOnceContent?
}
