//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Upload.Constants {
    public static let resourceUploadProgressNotification = NSNotification.Name("ResourceUploadProgressNotification")
    // uploadProgressKey already defined for v2 attachments and can be reused here.
    public static let uploadResourceIDKey = "UploadResourceIDKey"
}
