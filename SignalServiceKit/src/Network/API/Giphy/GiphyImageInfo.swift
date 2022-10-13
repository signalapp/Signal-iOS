//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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

// Represents a single Giphy image.
@objc
public class GiphyImageInfo: NSObject {
    public let giphyId: String
    private let assets: [GiphyAsset]

    init?(parsing dictionary: [String: Any]) {
        guard let idString = dictionary["id"] as? String,
              let renditionDict = (dictionary["images"] as? [String: [String: Any]]) else {
            Logger.warn("Missing required parameters")
            return nil
        }

        giphyId = idString
        assets = renditionDict.flatMap { (rendition, dict) in
            GiphyAsset.parsing(renditionString: rendition, definition: dict)
        }

        super.init()

        guard giphyId.count > 0 else {
            Logger.error("Invalid id when parsing image info")
            return nil
        }
        guard isValidImage else {
            Logger.error("Missing required asset info")
            return nil
        }
    }

    // TODO: We may need to tweak these constants.
    let kValidPreviewDimensions: ClosedRange<CGFloat> = 60...618
    let kValidSendingDimensions: ClosedRange<CGFloat> = 101...618
    let kPreferedPreviewFileSize = Int(256 * 1024)
    let kPreferedSendingFileSize = Int(3 * 1024 * 1024)
}

extension GiphyImageInfo {

    public var isValidImage: Bool {
        [anyOriginalAsset, animatedPreviewAsset, fullSizeAsset]
            .allSatisfy { $0 != nil }
    }

    public var animatedPreviewAsset: GiphyAsset? {
        assets
            .filter { !$0.rendition.isStill }
            .filter { [.gif, .mp4].contains($0.type) }
            .filter { $0.dimensions.fits(range: kValidPreviewDimensions) }
            .filter { $0.size > 0 }
            .bestOption(forTargetSize: kPreferedPreviewFileSize)
    }

    public var fullSizeAsset: GiphyAsset? {
        let validTypes: [GiphyAsset.FileType] = [.gif, .mp4]

        return assets
            .filter { !$0.rendition.isStill }
            .filter { validTypes.contains($0.type) }
            .filter { $0.dimensions.fits(range: kValidSendingDimensions) }
            .filter { $0.size > 0 }
            .bestOption(forTargetSize: kPreferedSendingFileSize)
    }

    public var originalAspectRatio: CGFloat {
        // Only the original rendition has the aspect ratio source of truth
        anyOriginalAsset.map { $0.dimensions.width / $0.dimensions.height } ?? 1.0
    }

    private var anyOriginalAsset: GiphyAsset? {
        assets.first { $0.rendition == .original }
    }
}

private extension Sequence where Element == GiphyAsset {
    // Selects the largest element under the target size, or if not satisfiable,
    // the smallest element above the target size

    // Given a sequence of assets, returns...
    // - The largest dimensioned item under the target file size
    // - If unavailable, the item with the smallest file size over the target
    func bestOption(forTargetSize targetSize: Int) -> GiphyAsset? {
        let findLargestUnderBudget = {
            filter { $0.size <= targetSize }.max {
                // Order by increasing width. If equal, order by decreasing file size.
                if $0.dimensions.width != $1.dimensions.width {
                    return $0.dimensions.width < $1.dimensions.width
                } else {
                    return $0.size > $1.size
                }
            }
        }

        let budgetWindow = (targetSize+1..<Int(OWSMediaUtils.kMaxFileSizeImage))
        let findSmallestOverBudget = {
            filter { budgetWindow.contains($0.size) }.min {
                // Order by increasing file size. If equal, order by decreasing dimension.
                if $0.size != $1.size {
                    return $0.size < $1.size
                } else {
                    return $0.dimensions.width > $1.dimensions.width
                }
            }
        }
        return findLargestUnderBudget() ?? findSmallestOverBudget()
    }
}

private extension CGSize {
    func fits<T>(range: T) -> Bool where T: RangeExpression, T.Bound == CGFloat {
        range.contains(width) && range.contains(height)
    }
}

private extension URL {
    var giphyAssetFileExtension: String? {
        let urlExtension = pathExtension.lowercased()
        if ["gif", "mp4", "jpg"].contains(urlExtension) {
            return urlExtension
        } else {
            Logger.error("Invalid file extension from giphy")
            return nil
        }
    }
}
