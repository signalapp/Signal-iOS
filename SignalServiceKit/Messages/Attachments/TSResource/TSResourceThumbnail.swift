//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A TSResource for which we have the thumbnail data on local disk,
/// but not fullsize data.
/// Note that if we have fullsize data, we have no use for the thumbnail
/// and use ``TSResourceStream`` instead.
public protocol TSResourceThumbnail: TSResource {

    // Filepath to the thumbnail media on disk.
    var localRelativeFilePath: String { get }

    // MARK: - Cached media properties

    var cachedIsValidImage: Bool { get }
    var cachedIsValidVideo: Bool { get }
    var cachedIsAnimated: Bool { get }

    // These are nil if the media is not of the relevant type.

    var cachedImageSize: CGSize? { get }
    var cachedAudioDuration: TimeInterval? { get }
    var cachedVideoDuration: TimeInterval? { get }
}
