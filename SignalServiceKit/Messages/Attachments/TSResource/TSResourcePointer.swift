//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// TSResource that can be downloaded.
///
/// Today this is just a wrapper around a TSResource with non-nil transit cdn info, created when
/// we don't have local data.
/// Eventually, this could represent a downloadable transit tier pointer, media tier pointer, or thumbnail pointer.
/// 
/// Thus it is not a mutually exlusive subclass of TSResource; a TSResource could have a thumbnail downloaded
/// but not the fullsize media, so calling it _either_ a Pointer _or_ a Stream would be inaccurate.
public struct TSResourcePointer {

    public let resource: TSResource

    public let cdnNumber: UInt32
    public let cdnKey: String

    public init(
        resource: TSResource,
        cdnNumber: UInt32,
        cdnKey: String
    ) {
        self.resource = resource
        self.cdnNumber = cdnNumber
        self.cdnKey = cdnKey
    }
}
