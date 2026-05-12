//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UniformTypeIdentifiers

public enum GiphyError: Error {
    case assertionError(description: String)
    case fetchFailure
}

extension GiphyError: LocalizedError, UserErrorDescriptionProvider {
    public var errorDescription: String? {
        localizedDescription
    }

    public var localizedDescription: String {
        switch self {
        case .assertionError:
            return OWSLocalizedString("GIF_PICKER_ERROR_GENERIC", comment: "Generic error displayed when picking a GIF")
        case .fetchFailure:
            return OWSLocalizedString("GIF_PICKER_ERROR_FETCH_FAILURE", comment: "Error displayed when there is a failure fetching a GIF from the remote service.")
        }
    }
}

public struct GiphyImageInfo {
    public static let fileExtension = "mp4"
    public static let utiType = UTType.mpeg4Movie.identifier

    public let giphyId: String
    public let fullSize: ProxiedContentAssetDescription
    public let preview: ProxiedContentAssetDescription
    public let previewAspectRatio: CGFloat
}
