//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Just a simple structure holding a resource and a reference to it,
/// since that's something we need to do very often.
public struct ReferencedTSResource {
    public let reference: TSResourceReference
    public let attachment: TSResource

    public init(reference: TSResourceReference, attachment: TSResource) {
        self.reference = reference
        self.attachment = attachment
    }
}

extension ReferencedAttachment {

    var referencedTSResource: ReferencedTSResource {
        return .init(reference: reference, attachment: attachment)
    }
}
