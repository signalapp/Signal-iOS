//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import SignalUI

public class CVMediaAlbumView: ManualStackViewWithLayer {
    private var items = [CVMediaAlbumItem]()
    private var isBorderless = false

    public var itemViews = [CVMediaView]()

    public var moreItemsView: CVMediaView?

    private static let kSpacingPts: CGFloat = 2
    private static let kMaxItems = 5

    // Not all of these sub-stacks maybe used.
    private let subStack1 = ManualStackView(name: "CVMediaAlbumView.subStack1")
    private let subStack2 = ManualStackView(name: "CVMediaAlbumView.subStack2")

    @available(*, unavailable, message: "use other init() instead.")
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable, message: "use other init() instead.")
    public required init(name: String, arrangedSubviews: [UIView] = []) {
        fatalError("init(name:arrangedSubviews:) has not been implemented")
    }

    public required init() {
        super.init(name: "media album view")
    }

    public func configure(mediaCache: CVMediaCache,
                          items: [CVMediaAlbumItem],
                          interaction: TSInteraction,
                          isBorderless: Bool,
                          cellMeasurement: CVCellMeasurement,
                          conversationStyle: ConversationStyle) {

        guard let maxMessageWidth = cellMeasurement.value(key: Self.measurementKey_maxMessageWidth) else {
            owsFailDebug("Missing maxMessageWidth.")
            return
        }
        guard let imageArrangementWrapper: CVMeasurementImageArrangement = cellMeasurement.object(key: Self.measurementKey_imageArrangement) else {
            owsFailDebug("Missing imageArrangement.")
            return
        }
        let imageArrangement = imageArrangementWrapper.imageArrangement

        self.items = items

        let viewSizePoints = imageArrangement.worstCaseMediaRenderSizePoints(conversationStyle: conversationStyle)
        self.itemViews = CVMediaAlbumView.itemsToDisplay(forItems: items).map { item in
            let thumbnailQuality = Self.thumbnailQuality(mediaSizePoints: item.mediaSize,
                                                         viewSizePoints: viewSizePoints)
            return CVMediaView(mediaCache: mediaCache,
                               attachment: item.attachment,
                               interaction: interaction,
                               maxMessageWidth: maxMessageWidth,
                               isBorderless: isBorderless,
                               isBroken: item.isBroken,
                               thumbnailQuality: thumbnailQuality,
                               conversationStyle: conversationStyle)
        }

        self.isBorderless = isBorderless
        self.backgroundColor = isBorderless ? .clear : Theme.backgroundColor

        createContents(imageArrangement: imageArrangement,
                       cellMeasurement: cellMeasurement)
    }

    public override func reset() {
        super.reset()

        subStack1.reset()
        subStack2.reset()

        items.removeAll()
        itemViews.removeAll()
        moreItemsView = nil

        removeAllSubviews()
    }

    private func createContents(imageArrangement: ImageArrangement,
                                cellMeasurement: CVCellMeasurement) {

        let outerStackView = self
        let subStack1 = self.subStack1
        let subStack2 = self.subStack2

        subStack1.reset()
        subStack2.reset()

        var outerViews = [UIView]()
        let imageGroup1 = imageArrangement.imageGroup1
        let itemViews1 = Array(itemViews.prefix(imageGroup1.imageCount))
        subStack1.configure(config: imageArrangement.innerStackConfig,
                            cellMeasurement: cellMeasurement,
                            measurementKey: Self.measurementKey_substack1,
                            subviews: itemViews1)
        outerViews.append(subStack1)

        if let imageGroup2 = imageArrangement.imageGroup2 {
            owsAssertDebug(itemViews.count == imageGroup1.imageCount + imageGroup2.imageCount)

            let itemViews2 = Array(itemViews.suffix(from: imageGroup1.imageCount))

            if items.count > CVMediaAlbumView.kMaxItems {
                guard let lastView = itemViews2.last else {
                    owsFailDebug("Missing lastView")
                    return
                }

                moreItemsView = lastView

                let tintView = UIView()
                tintView.backgroundColor = UIColor(white: 0, alpha: 0.4)
                lastView.addSubview(tintView)
                subStack2.layoutSubviewToFillSuperviewEdges(tintView)

                let moreCount = max(1, items.count - CVMediaAlbumView.kMaxItems)
                let moreCountText = OWSFormat.formatInt(moreCount)
                let moreText = String(format: OWSLocalizedString("MEDIA_GALLERY_MORE_ITEMS_FORMAT",
                                                                comment: "Format for the 'more items' indicator for media galleries. Embeds {{the number of additional items}}."),
                                      moreCountText)
                let moreLabel = CVLabel()
                moreLabel.text = moreText
                moreLabel.textColor = UIColor.ows_white
                // We don't want to use dynamic text here.
                moreLabel.font = UIFont.systemFont(ofSize: 24)
                lastView.addSubview(moreLabel)
                subStack2.addLayoutBlock { _ in
                    let labelSize = moreLabel.sizeThatFitsMaxSize
                    let labelOrigin = ((lastView.bounds.size - labelSize) * 0.5).asPoint
                    moreLabel.frame = CGRect(origin: labelOrigin, size: labelSize)
                }
            }

            subStack2.configure(config: imageArrangement.innerStackConfig,
                                cellMeasurement: cellMeasurement,
                                measurementKey: Self.measurementKey_substack2,
                                subviews: itemViews2)
            outerViews.append(subStack2)
        } else {
            owsAssertDebug(itemViews.count == imageGroup1.imageCount)
        }

        outerStackView.configure(config: imageArrangement.outerStackConfig,
                                 cellMeasurement: cellMeasurement,
                                 measurementKey: Self.measurementKey_outerStack,
                                 subviews: outerViews)

        for itemView in itemViews {
            guard moreItemsView != itemView else {
                // Don't display the caption indicator on
                // the "more" item, if any.
                continue
            }
            guard let index = itemViews.firstIndex(of: itemView) else {
                owsFailDebug("Couldn't determine index of item view.")
                continue
            }
            let item = items[index]
            guard let caption = item.caption else {
                continue
            }
            if caption.isEmpty {
                continue
            }
            guard let icon = UIImage(named: "media_album_caption") else {
                owsFailDebug("Couldn't load icon.")
                continue
            }
            let iconView = CVImageView(image: icon)
            itemView.addSubview(iconView)
            itemView.addLayoutBlock { view in
                let inset: CGFloat = 6
                let x = (CurrentAppContext().isRTL
                            ? view.width - (icon.size.width + inset)
                            : inset)
                iconView.frame = CGRect(x: x,
                                        y: inset,
                                        width: icon.size.width,
                                        height: icon.size.height)
            }
        }
    }

    public func loadMedia() {
        for itemView in itemViews {
            itemView.loadMedia()
        }
    }

    public func unloadMedia() {
        for itemView in itemViews {
            itemView.unloadMedia()
        }
    }

    private class func itemsToDisplay(forItems items: [CVMediaAlbumItem]) -> [CVMediaAlbumItem] {
        // TODO: Unless design changes, we want to display
        //       items which are still downloading and invalid
        //       items.
        let validItems = items
        guard validItems.count < kMaxItems else {
            return Array(validItems[0..<kMaxItems])
        }
        return validItems
    }

    private static var hStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .horizontal,
                          alignment: .fill,
                          spacing: Self.kSpacingPts,
                          layoutMargins: .zero)
    }

    private static var vStackConfig: CVStackViewConfig {
        CVStackViewConfig(axis: .vertical,
                          alignment: .fill,
                          spacing: Self.kSpacingPts,
                          layoutMargins: .zero)
    }

    private static let measurementKey_maxMessageWidth: String = "CVMediaAlbumView.maxMessageWidth"
    private static let measurementKey_imageArrangement: String = "CVMediaAlbumView.imageArrangement"
    private static let measurementKey_outerStack = "CVMediaAlbumView.measurementKey_outerStack"
    private static let measurementKey_substack1 = "CVMediaAlbumView.measurementKey_substack1"
    private static let measurementKey_substack2 = "CVMediaAlbumView.measurementKey_substack2"

    public class func measure(maxWidth: CGFloat,
                              minWidth: CGFloat,
                              items: [CVMediaAlbumItem],
                              measurementBuilder: CVCellMeasurement.Builder) -> CGSize {

        func measureImageStackLayout(imageSize: CGSize,
                                     imageCount: Int,
                                     stackConfig: CVStackViewConfig,
                                     measurementKey: String) -> CGSize {
            let subviewInfos: [ManualStackSubviewInfo] = (0..<imageCount).map { _ in
                imageSize.asManualSubviewInfo
            }
            let stackMeasurement = ManualStackView.measure(config: stackConfig,
                                                           measurementBuilder: measurementBuilder,
                                                           measurementKey: measurementKey,
                                                           subviewInfos: subviewInfos)
            return stackMeasurement.measuredSize
        }

        let imageArrangement = Self.imageArrangement(minWidth: minWidth,
                                                     maxWidth: maxWidth,
                                                     items: items)

        measurementBuilder.setObject(key: Self.measurementKey_imageArrangement,
                                     value: CVMeasurementImageArrangement(imageArrangement: imageArrangement))
        measurementBuilder.setValue(key: Self.measurementKey_maxMessageWidth, value: maxWidth)

        var groupInfos = [ManualStackSubviewInfo]()
        let imageGroup1 = imageArrangement.imageGroup1
        groupInfos.append(measureImageStackLayout(imageSize: imageGroup1.imageSize,
                                                  imageCount: imageGroup1.imageCount,
                                                  stackConfig: imageArrangement.innerStackConfig,
                                                  measurementKey: Self.measurementKey_substack1).asManualSubviewInfo)
        if let imageGroup2 = imageArrangement.imageGroup2 {
            groupInfos.append(measureImageStackLayout(imageSize: imageGroup2.imageSize,
                                                      imageCount: imageGroup2.imageCount,
                                                      stackConfig: imageArrangement.innerStackConfig,
                                                      measurementKey: Self.measurementKey_substack2).asManualSubviewInfo)
        }
        let outerStackMeasurement = ManualStackView.measure(config: imageArrangement.outerStackConfig,
                                                            measurementBuilder: measurementBuilder,
                                                            measurementKey: Self.measurementKey_outerStack,
                                                            subviewInfos: groupInfos,
                                                            maxWidth: maxWidth)
        return outerStackMeasurement.measuredSize
    }

    fileprivate struct ImageGroup: Equatable {
        let imageCount: Int
        let imageSize: CGSize

        var imageSizes: [CGSize] {
            [CGSize](repeating: imageSize, count: imageCount)
        }
    }

    fileprivate enum ImageArrangement: Equatable {
        case single(row: ImageGroup)
        case oneHorizontalRow(row: ImageGroup)
        case twoHorizontalRows(row1: ImageGroup, row2: ImageGroup)
        case twoVerticalColumns(column1: ImageGroup, column2: ImageGroup)

        var outerStackConfig: CVStackViewConfig {
            switch self {
            case .single,
                 .oneHorizontalRow,
                 .twoHorizontalRows:
                return CVMediaAlbumView.vStackConfig
            case .twoVerticalColumns:
                return CVMediaAlbumView.hStackConfig
            }
        }

        var innerStackConfig: CVStackViewConfig {
            switch self {
            case .single,
                 .oneHorizontalRow,
                 .twoHorizontalRows:
                return CVMediaAlbumView.hStackConfig
            case .twoVerticalColumns:
                return CVMediaAlbumView.vStackConfig
            }
        }

        var imageGroup1: ImageGroup {
            switch self {
            case .single(let row):
                return row
            case .oneHorizontalRow(let row):
                return row
            case .twoHorizontalRows(let row1, _):
                return row1
            case .twoVerticalColumns(let column1, _):
                return column1
            }
        }

        var imageGroup2: ImageGroup? {
            switch self {
            case .single:
                return nil
            case .oneHorizontalRow:
                return nil
            case .twoHorizontalRows(_, let row2):
                return row2
            case .twoVerticalColumns(_, let column2):
                return column2
            }
        }

        func worstCaseMediaRenderSizePoints(conversationStyle: ConversationStyle) -> CGSize {
            let maxMediaMessageWidth = conversationStyle.maxMediaMessageWidth

            func worstCaseMediaRenderSize(horizontalRow row: ImageGroup,
                                          rowSize: CGSize) -> CGSize {
                return CGSize(width: rowSize.width / CGFloat(row.imageCount),
                              height: rowSize.height)
            }

            switch self {
            case .single:
                return .square(maxMediaMessageWidth)
            default:
                let imageSizes = self.imageSizes
                return CGSize(width: imageSizes.map { $0.width }.reduce(0, max),
                              height: imageSizes.map { $0.height }.reduce(0, max))
            }
        }

        var imageSizes: [CGSize] {
            switch self {
            case .single(let row):
                return row.imageSizes
            case .oneHorizontalRow(let row):
                return row.imageSizes
            case .twoHorizontalRows(let row1, let row2):
                return row1.imageSizes + row2.imageSizes
            case .twoVerticalColumns(let column1, let column2):
                return column1.imageSizes + column2.imageSizes
            }
        }
    }

    fileprivate class CVMeasurementImageArrangement: CVMeasurementObject {
        fileprivate let imageArrangement: ImageArrangement

        fileprivate required init(imageArrangement: ImageArrangement) {
            self.imageArrangement = imageArrangement

            super.init()
        }

        // MARK: - Equatable

        public static func == (lhs: CVMeasurementImageArrangement, rhs: CVMeasurementImageArrangement) -> Bool {
            lhs.imageArrangement == rhs.imageArrangement
        }
    }

    private class func imageArrangement(minWidth: CGFloat,
                                        maxWidth: CGFloat,
                                        items: [CVMediaAlbumItem]) -> ImageArrangement {

        let itemCount = itemsToDisplay(forItems: items).count
        switch itemCount {
        case 0:
            // X
            // Reflects content size.
            owsFailDebug("Missing items.")

            let imageSize = CGSize(square: maxWidth)
            let row = ImageGroup(imageCount: 1, imageSize: imageSize)
            return .single(row: row)
        case 1:
            // X
            // Reflects content size.

            // TODO: I'm not sure this is yielding the ideal results,
            // e.g. for extremely wide or tall images.
            let buildSingleMediaSize = { () -> CGSize? in
                guard items.count == 1 else {
                    // More than one piece of media.
                    return nil
                }
                guard let mediaAlbumItem = items.first else {
                    owsFailDebug("Missing mediaAlbumItem.")
                    return nil
                }

                let mediaSize = mediaAlbumItem.mediaSize
                guard mediaSize.width > 0 && mediaSize.height > 0 else {
                    // This could be a pending or invalid attachment.
                    return nil
                }
                // Honor the content aspect ratio for single media.
                var contentAspectRatio = mediaSize.width / mediaSize.height
                // Clamp the aspect ratio so that very thin/wide content is presented
                // in a reasonable way.
                let minAspectRatio: CGFloat = 0.35
                let maxAspectRatio: CGFloat = 1 / minAspectRatio
                owsAssertDebug(minAspectRatio <= maxAspectRatio)
                contentAspectRatio = contentAspectRatio.clamp(minAspectRatio, maxAspectRatio)

                let maxMediaWidth: CGFloat = maxWidth
                let maxMediaHeight: CGFloat = maxWidth
                var mediaWidth: CGFloat = maxMediaHeight * contentAspectRatio

                // We may need to reserve space for a footer overlay.
                mediaWidth = max(mediaWidth, minWidth)

                var mediaHeight: CGFloat = maxMediaHeight
                if mediaWidth > maxMediaWidth {
                    mediaWidth = maxMediaWidth
                    mediaHeight = maxMediaWidth / contentAspectRatio
                }

                // We don't want to blow up small images unnecessarily.
                let minimumSize: CGFloat = max(150, minWidth)
                let shortSrcDimension: CGFloat = min(mediaSize.width, mediaSize.height)
                let shortDstDimension: CGFloat = min(mediaWidth, mediaHeight)
                if shortDstDimension > minimumSize && shortDstDimension > shortSrcDimension {
                    let factor: CGFloat = minimumSize / shortDstDimension
                    mediaWidth *= factor
                    mediaHeight *= factor
                }

                return CGSize(width: mediaWidth, height: mediaHeight).round
            }

            let imageSize = buildSingleMediaSize() ?? CGSize(square: maxWidth)
            let row = ImageGroup(imageCount: 1, imageSize: imageSize)
            return .single(row: row)
        case 2:
            // X X
            // side-by-side.
            let imageSize = CGSize(square: floor((maxWidth - kSpacingPts) / 2))
            return .oneHorizontalRow(row: ImageGroup(imageCount: 2, imageSize: imageSize))
        case 3:
            //   x
            // X x
            // Big on left, 2 small on right.
            let smallImageSize: CGFloat = floor((maxWidth - kSpacingPts * 2) / 3)
            let bigImageSize: CGFloat = smallImageSize * 2 + kSpacingPts
            return .twoVerticalColumns(column1: ImageGroup(imageCount: 1, imageSize: .square(bigImageSize)),
                                       column2: ImageGroup(imageCount: 2, imageSize: .square(smallImageSize)))
        case 4:
            // XX
            // XX
            // Square
            let imageSize = CGSize(square: floor((maxWidth - CVMediaAlbumView.kSpacingPts) / 2))
            return .twoHorizontalRows(row1: ImageGroup(imageCount: 2, imageSize: imageSize),
                                       row2: ImageGroup(imageCount: 2, imageSize: imageSize))
        default:
            // X X
            // xxx
            // 2 big on top, 3 small on bottom.
            let bigImageSize: CGFloat = floor((maxWidth - kSpacingPts) / 2)
            let smallImageSize: CGFloat = floor((maxWidth - kSpacingPts * 2) / 3)
            return .twoHorizontalRows(row1: ImageGroup(imageCount: 2, imageSize: .square(bigImageSize)),
                                       row2: ImageGroup(imageCount: 3, imageSize: .square(smallImageSize)))
        }
    }

    public func mediaView(forLocation location: CGPoint) -> CVMediaView? {
        var bestMediaView: CVMediaView?
        var bestDistance: CGFloat = 0
        for itemView in itemViews {
            let itemCenter = convert(itemView.center, from: itemView.superview)
            let distance = location.distance(itemCenter)
            if bestMediaView != nil && distance > bestDistance {
                continue
            }
            bestMediaView = itemView
            bestDistance = distance
        }
        return bestMediaView
    }

    public func isMoreItemsView(mediaView: CVMediaView) -> Bool {
        return moreItemsView == mediaView
    }

    private static func thumbnailQuality(mediaSizePoints: CGSize,
                                         viewSizePoints: CGSize) -> AttachmentThumbnailQuality {
        guard mediaSizePoints.isNonEmpty,
              viewSizePoints.isNonEmpty else {
            owsFailDebug("Invalid sizes. mediaSizePoints: \(mediaSizePoints), viewSizePoints: \(viewSizePoints).")
            return .medium
        }
        // Determine render size for .scaleAspectFill.
        let renderSizeByWidth = CGSize(width: viewSizePoints.width,
                                       height: viewSizePoints.width * mediaSizePoints.height / mediaSizePoints.width)
        let renderSizeByHeight = CGSize(width: viewSizePoints.height * mediaSizePoints.width / mediaSizePoints.height,
                                       height: viewSizePoints.height)
        let renderSizePoints = (renderSizeByWidth.width > renderSizeByHeight.width
                                    ? renderSizeByWidth
                                    : renderSizeByHeight)
        let renderDimensionPoints = renderSizePoints.largerAxis
        let quality: AttachmentThumbnailQuality = {
            // Find the smallest quality of acceptable size.
            let qualities: [AttachmentThumbnailQuality] = [
                .small,
                .medium,
                .mediumLarge
                // Skip .large
            ]
            for quality in qualities {
                // The image will .scaleAspectFill the bounds of the media view.
                // We want to ensure that we more-or-less have sufficient pixel
                // data for the screen. There are only a few thumbnail sizes,
                // so falling over to the next largest size is expensive. Therefore
                // we include a small measure of slack in our calculation.
                //
                // targetQuality is expressed in terms of "the worst case ratio of
                // image pixels per screen pixels that we will accept."
                let targetQuality: CGFloat = 0.8
                let sizeTolerance: CGFloat = 1 / targetQuality
                let thumbnailDimensionPoints = TSAttachmentStream.thumbnailDimensionPoints(forThumbnailQuality: quality)
                if renderDimensionPoints <= CGFloat(thumbnailDimensionPoints) * sizeTolerance {
                    return quality
                }
            }
            return .large
        }()
        return quality
    }
}

// MARK: -

public struct CVMediaAlbumItem: Equatable {
    public let attachment: TSAttachment

    // This property will only be set if the attachment is downloaded and valid.
    public let attachmentStream: TSAttachmentStream?

    public let caption: String?

    // This property will be non-zero if the attachment is valid.
    //
    // TODO: Add units to name.
    public let mediaSize: CGSize

    public let isBroken: Bool
    public var isFailedDownload: Bool {
        guard let attachmentPointer = attachment as? TSAttachmentPointer else {
            return false
        }
        return attachmentPointer.state == .failed
    }

    public var isPendingMessageRequest: Bool {
        guard let attachmentPointer = attachment as? TSAttachmentPointer else {
            return false
        }
        return attachmentPointer.state == .pendingMessageRequest
    }
}
