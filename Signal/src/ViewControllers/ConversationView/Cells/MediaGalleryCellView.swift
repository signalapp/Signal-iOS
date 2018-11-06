//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSMediaGalleryCellView)
public class MediaGalleryCellView: UIStackView {
    private let items: [ConversationMediaGalleryItem]
    private let itemViews: [ConversationMediaView]

    private static let kSpacingPts: CGFloat = 2
    private static let kMaxItems = 5

    @objc
    public required init(mediaCache: NSCache<NSString, AnyObject>,
                         items: [ConversationMediaGalleryItem],
                         maxMessageWidth: CGFloat) {
        self.items = items
        self.itemViews = MediaGalleryCellView.itemsToDisplay(forItems: items).map {
            ConversationMediaView(mediaCache: mediaCache,
                          attachment: $0.attachment)
        }

        super.init(frame: .zero)

        backgroundColor = Theme.backgroundColor

        createContents(maxMessageWidth: maxMessageWidth)
    }

    private func createContents(maxMessageWidth: CGFloat) {
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
            let imageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts) / 2
            autoSet(viewSize: imageSize, ofViews: itemViews)
            for itemView in itemViews {
                addArrangedSubview(itemView)
            }
            self.axis = .horizontal
            self.spacing = MediaGalleryCellView.kSpacingPts
        case 3:
            //   x
            // X x
            // Big on left, 2 small on right.
            let smallImageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts * 2) / 3
            let bigImageSize = smallImageSize * 2 + MediaGalleryCellView.kSpacingPts

            guard let leftItemView = itemViews.first else {
                owsFailDebug("Missing view")
                return
            }
            autoSet(viewSize: bigImageSize, ofViews: [leftItemView])
            addArrangedSubview(leftItemView)

            let rightViews = Array(itemViews[1..<3])
            addArrangedSubview(newRow(rowViews: rightViews,
                                      axis: .vertical,
                                      viewSize: smallImageSize))
            self.axis = .horizontal
            self.spacing = MediaGalleryCellView.kSpacingPts
        case 4:
            // X X
            // X X
            // Square
            let imageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts) / 2

            let topViews = Array(itemViews[0..<2])
            addArrangedSubview(newRow(rowViews: topViews,
                                      axis: .horizontal,
                                      viewSize: imageSize))

            let bottomViews = Array(itemViews[2..<4])
            addArrangedSubview(newRow(rowViews: bottomViews,
                                      axis: .horizontal,
                                      viewSize: imageSize))

            self.axis = .vertical
            self.spacing = MediaGalleryCellView.kSpacingPts
        default:
            // X X
            // xxx
            // 2 big on top, 3 small on bottom.
            let bigImageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts) / 2
            let smallImageSize = (maxMessageWidth - MediaGalleryCellView.kSpacingPts * 2) / 3

            let topViews = Array(itemViews[0..<2])
            addArrangedSubview(newRow(rowViews: topViews,
                                      axis: .horizontal,
                                      viewSize: bigImageSize))

            let bottomViews = Array(itemViews[2..<5])
            addArrangedSubview(newRow(rowViews: bottomViews,
                                      axis: .horizontal,
                                      viewSize: smallImageSize))

            self.axis = .vertical
            self.spacing = MediaGalleryCellView.kSpacingPts

            if items.count > MediaGalleryCellView.kMaxItems {
                guard let lastView = bottomViews.last else {
                    owsFailDebug("Missing lastView")
                    return
                }

                let tintView = UIView()
                tintView.backgroundColor = UIColor(white: 0, alpha: 0.4)
                lastView.addSubview(tintView)
                tintView.autoPinEdgesToSuperviewEdges()

                let moreCount = max(1, items.count - MediaGalleryCellView.kMaxItems)
                let moreCountText = OWSFormat.formatInt(Int32(moreCount))
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
    }

    private func autoSet(viewSize: CGFloat,
                         ofViews views: [ConversationMediaView]
                        ) {
        for itemView in views {
            itemView.autoSetDimensions(to: CGSize(width: viewSize, height: viewSize))
        }
    }

    private func newRow(rowViews: [ConversationMediaView],
                        axis: NSLayoutConstraint.Axis,
                        viewSize: CGFloat) -> UIStackView {
        autoSet(viewSize: viewSize, ofViews: rowViews)
        return newRow(rowViews: rowViews, axis: axis)
    }

    private func newRow(rowViews: [ConversationMediaView],
                        axis: NSLayoutConstraint.Axis) -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: rowViews)
        stackView.axis = axis
        stackView.spacing = MediaGalleryCellView.kSpacingPts
        return stackView
    }

    @objc
    public func loadMedia() {
        for itemView in itemViews {
            itemView.loadMedia()
        }
    }

    @objc
    public func unloadMedia() {
        for itemView in itemViews {
            itemView.unloadMedia()
        }
    }

    @available(*, unavailable, message: "use other init() instead.")
    required public init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    private class func itemsToDisplay(forItems items: [ConversationMediaGalleryItem]) -> [ConversationMediaGalleryItem] {
        // TODO: Unless design changes, we want to display
        //       items which are still downloading and invalid
        //       items.
        let validItems = items
        guard validItems.count < kMaxItems else {
            return Array(validItems[0..<kMaxItems])
        }
        return validItems
    }

    @objc
    public class func layoutSize(forMaxMessageWidth maxMessageWidth: CGFloat,
                                 items: [ConversationMediaGalleryItem]) -> CGSize {
        let itemCount = itemsToDisplay(forItems: items).count
        switch itemCount {
        case 0, 1, 4:
            // X
            //
            // or
            //
            // XX
            // XX
            // Square
            return CGSize(width: maxMessageWidth, height: maxMessageWidth)
        case 2:
            // X X
            // side-by-side.
            let imageSize = (maxMessageWidth - kSpacingPts) / 2
            return CGSize(width: maxMessageWidth, height: imageSize)
        case 3:
            //   x
            // X x
            // Big on left, 2 small on right.
            let smallImageSize = (maxMessageWidth - kSpacingPts * 2) / 3
            let bigImageSize = smallImageSize * 2 + kSpacingPts
            return CGSize(width: maxMessageWidth, height: bigImageSize)
        default:
            // X X
            // xxx
            // 2 big on top, 3 small on bottom.
            let bigImageSize = (maxMessageWidth - kSpacingPts) / 2
            let smallImageSize = (maxMessageWidth - kSpacingPts * 2) / 3
            return CGSize(width: maxMessageWidth, height: bigImageSize + smallImageSize + kSpacingPts)
        }
    }
}
