//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Represents the information about a resource held by the _owner_
/// of that resource.
///
/// In plain english: legacy attachments put their attachmentId on
/// their owning message. v2 attachments instead put nothing, or
/// a boolean that says "this uses v2 attachments, go look on
/// the AttachmentReferences table". This represents that,
/// and some additional metadata available from the proto.
///
/// Different from a TSResourceId, because that contains either
/// a v1 uniqueId or a v2 row id; this has no row id in the v2 case,
/// and is typically used _before_ the v2 attachment is created
/// and therefore there is no row id.
public enum TSResourceRetrievalInfo {

    /// Legacy attachment reference.
    case legacy(uniqueId: String)

    /// V2 attachment reference. May or may not have an associated
    /// attachment; that information will live on the AttachmentReferences
    /// table and not on the owning object.
    case v2
}
