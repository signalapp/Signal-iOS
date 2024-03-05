//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class TSResourceManagerMock: TSResourceManager {

    public init() {}

    public func createBodyAttachmentPointers(from protos: [SSKProtoAttachmentPointer], message: TSMessage, tx: DBWriteTransaction) {
        // Do nothing
    }

    public func addBodyAttachments(_ attachments: [TSResource], to message: TSMessage, tx: DBWriteTransaction) {
        // Do nothing
    }

    public func removeBodyAttachment(_ attachment: TSResource, from message: TSMessage, tx: DBWriteTransaction) {
        // Do nothing
    }
}

#endif
