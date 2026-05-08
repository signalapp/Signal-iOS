//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UniformTypeIdentifiers

public class GiphyAsset: ProxiedContentAssetDescription {
    public static let fileExtension = "mp4"
    public static let utiType = UTType.mpeg4Movie.identifier

    let rendition: Rendition
    let dimensions: CGSize
    let size: Int

    static func parsing(renditionString: String, definition: [String: Any]) -> [GiphyAsset] {
        guard let rendition = Rendition(rawValue: renditionString) else { return [] }
        return parsing(rendition: rendition, definition: definition)
    }

    static func parsing(rendition: Rendition, definition: [String: Any]) -> [GiphyAsset] {
        // These keys are always required
        guard
            let width = parsePositiveInt(dict: definition, key: "width"),
            let height = parsePositiveInt(dict: definition, key: "height")
        else {
            let logDict = ["width": definition["width"], "height": definition["height"]]
            Logger.error("Error parsing \(rendition): \(logDict)")
            return []
        }
        let dimensions = CGSize(width: width, height: height)

        guard
            let url = parseUrl(dict: definition, key: "mp4"),
            let size = parsePositiveInt(dict: definition, key: "mp4_size"),
            let asset = GiphyAsset(rendition: rendition, dimensions: dimensions, url: url, size: size)
        else {
            Logger.error("No valid mp4 asset found while parsing: \(rendition)")
            return []
        }
        return [asset]
    }

    private init?(rendition: Rendition, dimensions: CGSize, url: URL, size: Int) {
        guard url.pathExtension.lowercased() == Self.fileExtension else { return nil }

        self.rendition = rendition
        self.dimensions = dimensions
        self.size = size
        super.init(url: url as NSURL, fileExtension: Self.fileExtension)
    }

    var assetDescription: ProxiedContentAssetDescription? {
        ProxiedContentAssetDescription(url: url as NSURL, fileExtension: Self.fileExtension)
    }
}

extension GiphyAsset {
    enum Rendition: String, RawRepresentable {
        // Original
        case original = "original"

        // Animated preview variants
        case preview = "preview"
        case previewGif = "preview_gif"

        // Full size variants
        case fixedHeight = "fixed_height"
        case fixedHeightSmall = "fixed_height_small"
        case fixedWidth = "fixed_width"
        case fixedWidthSmall = "fixed_width_small"
        case downsizedSmall = "downsized_small"
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
