//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AttachmentReference: TSResourceReference {
    public var resourceId: TSResourceId {
        fatalError("Unimplemented!")
    }

    public var concreteType: ConcreteTSResourceReference { .v2(self) }
}
