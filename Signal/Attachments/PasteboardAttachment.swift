//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import SignalUI
import UIKit
import UniformTypeIdentifiers

enum PasteboardAttachment {
    static func hasStickerAttachment() -> Bool {
        guard
            UIPasteboard.general.numberOfItems > 0,
            let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: IndexSet(integer: 0))
        else {
            return false
        }

        let stickerSet: Set<String> = ["com.apple.sticker", "com.apple.png-sticker"]
        let pasteboardUTISet = Set<String>(filterDynamicUTITypes(pasteboardUTITypes[0]))
        for utiType in pasteboardUTISet {
            if stickerSet.contains(utiType) {
                return true
            }
        }
        return false
    }

    static func mayHaveAttachments() -> Bool {
        return UIPasteboard.general.numberOfItems > 0
    }

    static func hasText() -> Bool {
        if UIPasteboard.general.numberOfItems < 1 {
            return false
        }
        let itemSet = IndexSet(integer: 0)
        guard let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: itemSet) else {
            return false
        }
        let pasteboardUTISet = Set<String>(filterDynamicUTITypes(pasteboardUTITypes[0]))
        guard pasteboardUTISet.count > 0 else {
            return false
        }

        // The mention text view has a special pasteboard type, if we see it
        // we know that the pasteboard contains text.
        guard !pasteboardUTISet.contains(BodyRangesTextView.pasteboardType) else {
            return true
        }

        // The pasteboard can be populated with multiple UTI types
        // with different payloads.  iMessage for example will copy
        // an animated GIF to the pasteboard with the following UTI
        // types:
        //
        // * "public.url-name"
        // * "public.utf8-plain-text"
        // * "com.compuserve.gif"
        //
        // We want to paste the animated GIF itself, not it's name.
        //
        // In general, our rule is to prefer non-text pasteboard
        // contents, so we return true IFF there is a text UTI type
        // and there is no non-text UTI type.
        var hasTextUTIType = false
        var hasNonTextUTIType = false
        for utiType in pasteboardUTISet {
            if let type = UTType(utiType), type.conforms(to: .text) {
                hasTextUTIType = true
            } else if SignalAttachment.mediaUTISet.contains(utiType) {
                hasNonTextUTIType = true
            }
        }
        if pasteboardUTISet.contains(UTType.url.identifier) {
            // Treat URL as a textual UTI type.
            hasTextUTIType = true
        }
        if hasNonTextUTIType {
            return false
        }
        return hasTextUTIType
    }

    // Discard "dynamic" UTI types since our attachment pipeline
    // requires "standard" UTI types to work properly, e.g. when
    // mapping between UTI type, MIME type and file extension.
    private static func filterDynamicUTITypes(_ types: [String]) -> [String] {
        return types.filter { !$0.hasPrefix("dyn") }
    }

    /// Returns an attachment from the pasteboard, or nil if no attachment
    /// can be found.
    static func loadPreviewableAttachments() async throws -> [PreviewableAttachment]? {
        guard
            UIPasteboard.general.numberOfItems >= 1,
            let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: nil)
        else {
            return nil
        }

        var attachments = [PreviewableAttachment]()
        for (index, utiSet) in pasteboardUTITypes.enumerated() {
            let attachment = try await loadPreviewableAttachment(
                atIndex: IndexSet(integer: index),
                pasteboardUTIs: utiSet,
                retrySinglePixelImages: true,
            )

            guard let attachment else {
                owsFailDebug("Missing attachment")
                continue
            }

            if attachments.isEmpty {
                if !canEverHaveMultipleAttachments(ifAlreadyHaveAttachment: attachment) {
                    // If this is a non-visual-media attachment, we only allow 1 pasted item at a time.
                    return [attachment]
                }
            }

            // Otherwise, continue with any visual media attachments, dropping
            // any non-visual-media ones based on the first pasteboard item.
            if canEverHaveMultipleAttachments(ifAlreadyHaveAttachment: attachment) {
                attachments.append(attachment)
            } else {
                Logger.warn("Dropping non-visual media attachment in paste action")
            }
        }
        return attachments
    }

    private static func canEverHaveMultipleAttachments(ifAlreadyHaveAttachment attachment: PreviewableAttachment) -> Bool {
        return attachment.isVisualMedia && !attachment.rawValue.isBorderless
    }

    private static func loadPreviewableAttachment(atIndex index: IndexSet, pasteboardUTIs: [String], retrySinglePixelImages: Bool) async throws -> PreviewableAttachment? {
        var pasteboardUTISet = Set<String>(filterDynamicUTITypes(pasteboardUTIs))
        guard pasteboardUTISet.count > 0 else {
            return nil
        }

        // If we have the choice between a png and a jpg, always choose
        // the png as it may have transparency. Apple provides both jpg
        //  and png uti types when sending memoji stickers and
        // `inputImageUTISet` is unordered, so without this check there
        // is a 50/50 chance that we'd pick the jpg.
        if pasteboardUTISet.isSuperset(of: [UTType.jpeg.identifier, UTType.png.identifier]) {
            pasteboardUTISet.remove(UTType.jpeg.identifier)
        }

        for dataUTI in SignalAttachment.inputImageUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let dataSource = buildDataSource(atIndex: index, dataUTI: dataUTI) else {
                    return nil
                }
                // There is a known bug with the iOS pasteboard where it will randomly give a
                // single green pixel, and nothing else. Work around this by refetching the
                // pasteboard after a brief delay (once, then give up).
                if retrySinglePixelImages, (try? dataSource.imageSource())?.imageMetadata(ignorePerTypeFileSizeLimits: true)?.pixelSize == CGSize(square: 1) {
                    try? await Task.sleep(nanoseconds: NSEC_PER_MSEC * 50)
                    return try await loadPreviewableAttachment(atIndex: index, pasteboardUTIs: pasteboardUTIs, retrySinglePixelImages: false)
                }

                return try PreviewableAttachment.imageAttachment(dataSource: dataSource, dataUTI: dataUTI, canBeBorderless: true)
            }
        }
        for dataUTI in SignalAttachment.videoUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let dataSource = buildDataSource(atIndex: index, dataUTI: dataUTI) else {
                    return nil
                }

                // [15M] TODO: Don't ignore errors for pasteboard videos.
                return try? await PreviewableAttachment.compressVideoAsMp4(dataSource: dataSource)
            }
        }
        for dataUTI in SignalAttachment.audioUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let dataSource = buildDataSource(atIndex: index, dataUTI: dataUTI) else {
                    return nil
                }
                return try PreviewableAttachment.audioAttachment(dataSource: dataSource, dataUTI: dataUTI)
            }
        }

        let dataUTI = pasteboardUTISet[pasteboardUTISet.startIndex]
        guard let dataSource = buildDataSource(atIndex: index, dataUTI: dataUTI) else {
            return nil
        }
        return try PreviewableAttachment.genericAttachment(dataSource: dataSource, dataUTI: dataUTI)
    }

    public static func loadPreviewableStickerAttachment() throws -> PreviewableAttachment? {
        guard
            UIPasteboard.general.numberOfItems >= 1,
            let pasteboardUTITypes = UIPasteboard.general.types(forItemSet: IndexSet(integer: 0))
        else {
            return nil
        }

        var pasteboardUTISet = Set<String>(filterDynamicUTITypes(pasteboardUTITypes[0]))
        guard pasteboardUTISet.count > 0 else {
            return nil
        }

        // If we have the choice between a png and a jpg, always choose
        // the png as it may have transparency.
        if pasteboardUTISet.isSuperset(of: [UTType.jpeg.identifier, UTType.png.identifier]) {
            pasteboardUTISet.remove(UTType.jpeg.identifier)
        }

        for dataUTI in SignalAttachment.inputImageUTISet {
            if pasteboardUTISet.contains(dataUTI) {
                guard let dataSource = buildDataSource(atIndex: IndexSet(integer: 0), dataUTI: dataUTI) else {
                    return nil
                }
                let result = try PreviewableAttachment.imageAttachment(dataSource: dataSource, dataUTI: dataUTI, canBeBorderless: true)
                if !result.rawValue.isBorderless {
                    owsFailDebug("treating non-sticker data as a sticker")
                    result.rawValue.isBorderless = true
                }
                return result
            }
        }
        return nil
    }

    /// Returns an attachment from the memoji.
    public static func loadPreviewableMemojiAttachment(fromMemojiGlyph memojiGlyph: OWSAdaptiveImageGlyph) throws -> PreviewableAttachment {
        let dataUTI = filterDynamicUTITypes([memojiGlyph.contentType.identifier]).first
        guard let dataUTI else {
            throw SignalAttachmentError.invalidFileFormat
        }
        let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI)
        guard let fileExtension else {
            throw SignalAttachmentError.missingData
        }
        let dataSource = try DataSourcePath(writingTempFileData: memojiGlyph.imageContent, fileExtension: fileExtension)
        return try PreviewableAttachment.imageAttachment(dataSource: dataSource, dataUTI: dataUTI, canBeBorderless: true)
    }

    private static func buildDataSource(atIndex index: IndexSet, dataUTI: String) -> DataSourcePath? {
        guard
            let dataValue = dataForPasteboardItem(atIndex: index, dataUTI: dataUTI),
            let fileExtension = MimeTypeUtil.fileExtensionForUtiType(dataUTI),
            let dataSource = try? DataSourcePath(writingTempFileData: dataValue, fileExtension: fileExtension)
        else {
            owsFailDebug("Failed to build data source from pasteboard data for UTI: \(dataUTI)")
            return nil
        }
        return dataSource
    }

    private static func dataForPasteboardItem(atIndex index: IndexSet, dataUTI: String) -> Data? {
        return UIPasteboard.general.data(forPasteboardType: dataUTI, inItemSet: index)?.first
    }
}
