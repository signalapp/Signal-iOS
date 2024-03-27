//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import CoreServices

public class GiphyAsset: ProxiedContentAssetDescription {
    let rendition: Rendition
    let dimensions: CGSize
    let size: Int
    public let type: FileType

    static func parsing(renditionString: String, definition: [String: Any]) -> [GiphyAsset] {
        guard let rendition = Rendition(rawValue: renditionString) else { return [] }
        return parsing(rendition: rendition, definition: definition)
    }

    static func parsing(rendition: Rendition, definition: [String: Any]) -> [GiphyAsset] {
        // These keys are always required
        guard let width = parsePositiveInt(dict: definition, key: "width"),
              let height = parsePositiveInt(dict: definition, key: "height") else {
            let logDict = ["width": definition["width"], "height": definition["height"]]
            Logger.error("Error parsing \(rendition): \(logDict)")
            return []
        }
        let dimensions = CGSize(width: width, height: height)
        var results: [GiphyAsset] = []

        // A given rendition may have multiple underlying assets.
        // First check for an mp4 specific url (must be of type mp4)
        if let url = parseUrl(dict: definition, key: "mp4"),
           let size = parsePositiveInt(dict: definition, key: "mp4_size"),
           let asset = GiphyAsset(rendition: rendition, dimensions: dimensions, url: url, size: size),
           asset.type == .mp4 {
            results.append(asset)
        }

        // Then check for anything keyed by "url" (can be any format)
        if let url = parseUrl(dict: definition, key: "url"),
           let size = parsePositiveInt(dict: definition, key: "size"),
           let asset = GiphyAsset(rendition: rendition, dimensions: dimensions, url: url, size: size) {
            results.append(asset)
        }

        if results.isEmpty {
            Logger.error("No valid assets found while parsing: \(rendition)")
        }
        return results
    }

    private init?(rendition: Rendition, dimensions: CGSize, url: URL, size: Int) {
        switch url.pathExtension.lowercased() {
        case "jpg": self.type = .jpg
        case "gif": self.type = .gif
        case "mp4": self.type = .mp4
        default: return nil
        }

        self.rendition = rendition
        self.dimensions = dimensions
        self.size = size
        super.init(url: url as NSURL, fileExtension: self.type.extension)
    }

    var assetDescription: ProxiedContentAssetDescription? {
        ProxiedContentAssetDescription(url: url as NSURL, fileExtension: type.extension)
    }
}

extension GiphyAsset {
    enum Rendition: String, RawRepresentable {
        // Original
        case original = "original"

        // Still variants
        case fixedHeightSmallStill = "fixed_height_small_still"
        case fixedHeightStill = "fixed_height_still"
        case fixedWidthSmallStill = "fixed_width_small_still"
        case fixedWidthStill = "fixed_width_still"
        case downsizedStill = "downsized_still"

        // Animated preview variants
        case preview = "preview"
        case previewGif = "preview_gif"

        // Full size variants
        case fixedHeight = "fixed_height"
        case fixedHeightSmall = "fixed_height_small"
        case fixedWidth = "fixed_width"
        case fixedWidthSmall = "fixed_width_small"
        case downsizedSmall = "downsized_small"

        var isStill: Bool {
            [.fixedHeightSmallStill,
             .fixedHeightStill,
             .fixedWidthSmallStill,
             .fixedWidthStill,
             .downsizedStill].contains(self)
        }
    }

    public enum FileType: Equatable {
        case jpg, gif, mp4

        public var `extension`: String {
            switch self {
            case .jpg: return "jpg"
            case .gif: return "gif"
            case .mp4: return "mp4"
            }
        }

        public var utiType: String {
            switch self {
            case .jpg: return kUTTypeJPEG as String
            case .gif: return kUTTypeGIF as String
            case .mp4: return kUTTypeMPEG4 as String
            }
        }
    }
}

private func parsePositiveInt(dict: [String: Any], key: String) -> Int? {
    let stringValue = dict[key] as? String
    let parsedValue = stringValue?.nilIfEmpty.flatMap { Int($0) } ?? 0
    return (parsedValue > 0) ? parsedValue : nil
}

private func parseUrl(dict: [String: Any], key: String) -> URL? {
    let stringValue = dict[key] as? String
    return stringValue?.nilIfEmpty.flatMap { URL(string: $0) }
}
