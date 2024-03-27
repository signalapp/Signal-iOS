//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Priority at which we download attachments.
///
/// Priority determines:
/// * Order in which we download (higher priority first)
/// * Whether we download while there is an active call (must be user initiated)
/// * Whether we download while the thread is in a message request state (must be user initiated)
/// * Whether we bypass auto-download settings (must be user initiated)
///
public enum AttachmentDownloadPriority: Int, Codable {
    case `default` = 50
    case userInitiated = 100

    // TODO: how should backup downloads interact with auto-download settings?
}
