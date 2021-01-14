//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public class CVMediaAlbumView: UIStackView {
    private var items = [CVMediaAlbumItem]()
    private var isBorderless = false

    public var itemViews = [CVMediaView]()

    public var moreItemsView: CVMediaView?

    private static let kSpacingPts: CGFloat = 2
    private static let kMaxItems = 5

    @available(*, unavailable, message: "use other init() instead.")
    required public init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public required init() {
        super.init(frame: .zero)
    }

    public func configure(mediaCache: NSCache<NSString, AnyObject>,
                          items: [CVMediaAlbumItem],
                          isOutgoing: Bool,
                          isBorderless: Bool,
                          cellMeasurement: CVCellMeasurement) {

        guard let maxMessageWidth = cellMeasurement.value(key: Self.maxMessageWidthKey) else {
            owsFailDebug("Missing maxMessageWidth.")
            return
        }

        self.items = items
        self.itemViews = CVMediaAlbumView.itemsToDisplay(forItems: items).map {
            CVMediaView(mediaCache: mediaCache,
                                  attachment: $0.attachment,
                                  isOutgoing: isOutgoing,
                                  maxMessageWidth: maxMessageWidth,
                                  isBorderless: isBorderless)
        }
        self.isBorderless = isBorderless

        // UIStackView's backgroundColor property has no effect.
        if !isBorderless {
            addBackgroundView(withBackgroundColor: Theme.backgroundColor)
        }

        createContents(cellMeasurement: cellMeasurement,
                       maxMessageWidth: maxMessageWidth)
    }

    public func reset() {
        items.removeAll()
        itemViews.removeAll()
        moreItemsView = nil

        removeAllSubviews()

        NSLayoutConstraint.deactivate(layoutConstraints)
        layoutConstraints = []
    }

    private var layoutConstraints = [NSLayoutConstraint]()

    private func createContents(cellMeasurement: CVCellMeasurement,
                                maxMessageWidth: CGFloat) {

        if let measuredSize = cellMeasurement.size(key: Self.measurementKey) {
            layoutConstraints.append(self.autoSetDimension(.height, toSize: measuredSize.height))
        } else {
            owsFailDebug("Missing measuredSize.")
        }

        for (index, itemView) in itemViews.enumerated() {
            if let measuredSize = cellMeasurement.size(key: Self.measurementKey(imageIndex: index)) {
                // The item heights should always exactly match the layout.
                layoutConstraints.append(itemView.autoSetDimension(.height, toSize: measuredSize.height))
                // The media album view's width might be larger than
                // expected due to other components in the message.
                //
                // Therefore item widths might need to adjust and
                // should not be required.
                NSLayoutConstraint.autoSetPriority(UILayoutPriority.defaultHigh) {
                    layoutConstraints.append(itemView.autoSetDimension(.width, toSize: measuredSize.width))
                }
            } else {
                owsFailDebug("Missing measuredSize for image.")
            }
        }

        switch itemViews.count {
        case 0:
            owsFailDebug("No item views.")
            return
        case 1:
            // X
            guard let itemView = itemViews.first else {
                owsFailDebug("Missing item view.")
                return
            }
            addSubview(itemView)
            itemView.autoPinEdgesToSuperviewEdges()
        case 2:
            // X X
            // side-by-side.
            for itemView in itemViews {
                addArrangedSubview(itemView)
            }
            self.axis = .horizontal
            self.spacing = CVMediaAlbumView.kSpacingPts
        case 3:
            //   x
            // X x
            // Big on left, 2 small on right.
            guard let leftItemView = itemViews.first else {
                owsFailDebug("Missing view")
                return
            }
            addArrangedSubview(leftItemView)

            let rightViews = Array(itemViews[1..<3])
            addArrangedSubview(newRow(rowViews: rightViews,
                                      axis: .vertical))
            self.axis = .horizontal
            self.spacing = CVMediaAlbumView.kSpacingPts
        case 4:
            // X X
            // X X
            // Square
            let topViews = Array(itemViews[0..<2])
            addArrangedSubview(newRow(rowViews: topViews,
                                      axis: .horizontal))

            let bottomViews = Array(itemViews[2..<4])
            addArrangedSubview(newRow(rowViews: bottomViews,
                                      axis: .horizontal))

            self.axis = .vertical
            self.spacing = CVMediaAlbumView.kSpacingPts
        default:
            // X X
            // xxx
            // 2 big on top, 3 small on bottom.
            let topViews = Array(itemViews[0..<2])
            addArrangedSubview(newRow(rowViews: topViews,
                                      axis: .horizontal))

            let bottomViews = Array(itemViews[2..<5])
            addArrangedSubview(newRow(rowViews: bottomViews,
                                      axis: .horizontal))

            self.axis = .vertical
            self.spacing = CVMediaAlbumView.kSpacingPts

            if items.count > CVMediaAlbumView.kMaxItems {
                guard let lastView = bottomViews.last else {
                    owsFailDebug("Missing lastView")
                    return
                }

                moreItemsView = lastView

                let tintView = UIView()
                tintView.backgroundColor = UIColor(white: 0, alpha: 0.4)
                lastView.addSubview(tintView)
                tintView.autoPinEdgesToSuperviewEdges()

                let moreCount = max(1, items.count - CVMediaAlbumView.kMaxItems)
                let moreCountText = OWSFormat.formatInt(moreCount)
                let moreText = String(format: NSLocalizedString("MEDIA_GALLERY_MORE_ITEMS_FORMAT",
                                                                comment: "Format for the 'more items' indicator for media galleries. Embeds {{the number of additional items}}."), moreCountText)
                let moreLabel = UILabel()
                moreLabel.text = moreText
                moreLabel.textColor = UIColor.ows_white
                // We don't want to use dynamic text here.
                moreLabel.font = UIFont.systemFont(ofSize: 24)
                lastView.addSubview(moreLabel)
                moreLabel.autoCenterInSuperview()
            }
        }

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
            guard caption.count > 0 else {
                continue
            }
            guard let icon = UIImage(named: "media_album_caption") else {
                owsFailDebug("Couldn't load icon.")
                continue
            }
            let iconView = UIImageView(image: icon)
            itemView.addSubview(iconView)
            itemView.layoutMargins = .zero
            iconView.autoPinTopToSuperviewMargin(withInset: 6)
            iconView.autoPinLeadingToSuperviewMargin(withInset: 6)
        }
    }

    private func newRow(rowViews: [CVMediaView],
                        axis: NSLayoutConstraint.Axis) -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: rowViews)
        stackView.axis = axis
        stackView.spacing = CVMediaAlbumView.kSpacingPts
        return stackView
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

    private static let measurementKey: String = "bodyMedia.album"
    private static let maxMessageWidthKey: String = "bodyMedia.maxMessageWidth"

    private class func measurementKey(imageIndex: Int) -> String {
        "bodyMedia.\(imageIndex)"
    }

    public class func layoutSize(maxWidth: CGFloat,
                                 minWidth: CGFloat,
                                 items: [CVMediaAlbumItem],
                                 measurementBuilder: CVCellMeasurement.Builder) -> CGSize {

        measurementBuilder.setValue(key: maxMessageWidthKey, value: maxWidth)

        let itemCount = itemsToDisplay(forItems: items).count
        switch itemCount {
        case 0:
            // X
            // Reflects content size.
            owsFailDebug("Missing items.")

            let size = CGSize(square: maxWidth)
            measurementBuilder.setSize(key: measurementKey(imageIndex: 0),
                                       size: size)
            measurementBuilder.setSize(key: measurementKey, size: size)
            return size
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
                    owsFailDebug("Invalid mediaSize.")
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

            let size = buildSingleMediaSize() ?? CGSize(square: maxWidth)
            measurementBuilder.setSize(key: measurementKey(imageIndex: 0),
                                       size: size)
            measurementBuilder.setSize(key: measurementKey, size: size)
            return size
        case 2:
            // X X
            // side-by-side.
            let imageSize = (maxWidth - kSpacingPts) / 2
            for index in [0, 1] {
                measurementBuilder.setSize(key: measurementKey(imageIndex: index),
                                           size: CGSize(square: imageSize))
            }
            let size = CGSize(width: maxWidth, height: imageSize)
            measurementBuilder.setSize(key: measurementKey, size: size)
            return size
        case 3:
            //   x
            // X x
            // Big on left, 2 small on right.
            let smallImageSize = (maxWidth - kSpacingPts * 2) / 3
            let bigImageSize = smallImageSize * 2 + kSpacingPts
            for index in [0] {
                measurementBuilder.setSize(key: measurementKey(imageIndex: index),
                                           size: CGSize(square: bigImageSize))
            }
            for index in [1, 2] {
                measurementBuilder.setSize(key: measurementKey(imageIndex: index),
                                           size: CGSize(square: smallImageSize))
            }
            let size = CGSize(width: maxWidth, height: bigImageSize)
            measurementBuilder.setSize(key: measurementKey, size: size)
            return size
        case 4:
            // XX
            // XX
            // Square
            let imageSize = CGSize(square: (maxWidth - CVMediaAlbumView.kSpacingPts) / 2)
            for index in 0..<max(1, itemCount) {
                measurementBuilder.setSize(key: measurementKey(imageIndex: index),
                                           size: imageSize)
            }
            let size = CGSize(square: maxWidth)
            measurementBuilder.setSize(key: measurementKey, size: size)
            return size
        default:
            // X X
            // xxx
            // 2 big on top, 3 small on bottom.
            let bigImageSize = (maxWidth - kSpacingPts) / 2
            let smallImageSize = (maxWidth - kSpacingPts * 2) / 3
            for index in [0, 1] {
                measurementBuilder.setSize(key: measurementKey(imageIndex: index),
                                           size: CGSize(square: bigImageSize))
            }
            for index in [2, 3, 4] {
                measurementBuilder.setSize(key: measurementKey(imageIndex: index),
                                           size: CGSize(square: smallImageSize))
            }
            let size = CGSize(width: maxWidth, height: bigImageSize + smallImageSize + kSpacingPts)
            measurementBuilder.setSize(key: measurementKey, size: size)
            return size
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
}

// MARK: -

public struct CVMediaAlbumItem: Equatable {
    public let attachment: TSAttachment

    // This property will only be set if the attachment is downloaded.
    public let attachmentStream: TSAttachmentStream?

    public let caption: String?

    // This property will be non-zero if the attachment is valid.
    public let mediaSize: CGSize

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
