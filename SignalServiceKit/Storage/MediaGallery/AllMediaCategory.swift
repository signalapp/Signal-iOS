//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Top level category for all media view
/// These are mutually exclusive and one is always selected.
public enum AllMediaCategory: Int, CaseIterable {
    case photoVideo = 0
    case audio = 1
    case otherFiles = 2
}

/// The filter we apply to the actual attachment files.
/// Each ``AllMediaCategory`` has its own set of filters the UI
/// allows the user to select from, as well as an "All" option that corresponds
/// to a "all" filter case, that is selected by default.
public enum AllMediaFilter: CaseIterable {

    // These cases correspond to the unfiltered top level categories.
    // They are a superset of all the subfilters below.
    case allPhotoVideoCategory
    case allAudioCategory
    // Files that don't fall into photo/video/audio category.
    case otherFiles

    // These cases are sub-filters for the photoVideo category.
    case gifs
    case videos
    case photos

    // These cases are sub-filters for the audio category.
    case voiceMessages
    case audioFiles

    public static func defaultMediaType(for fileType: AllMediaCategory) -> AllMediaFilter {
        switch fileType {
        case .photoVideo:
            return .allPhotoVideoCategory
        case .audio:
            return .allAudioCategory
        case .otherFiles:
            return .otherFiles
        }
    }
}
