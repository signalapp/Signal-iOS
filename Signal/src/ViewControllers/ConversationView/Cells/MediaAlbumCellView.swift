//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSMediaAlbumCellView)
public class MediaAlbumCellView: UIStackView {
    private let items: [ConversationMediaAlbumItem]

    @objc
    public let itemViews: [ConversationMediaView]

    @objc
    public var moreItemsView: ConversationMediaView?

    private static let kSpacingPts: CGFloat = 2
    private static let kMaxItems = 5

    @available(*, unavailable, message: "use other init() instead.")
    required public init(coder aDecoder: NSCoder) {
        notImplemented()
    }

    @objc
    public required init(mediaCache: NSCache<NSString, AnyObject>,
                         items: [ConversationMediaAlbumItem],
                         isOutgoing: Bool,
                         maxMessageWidth: CGFloat) {
        self.items = items
        self.itemViews = MediaAlbumCellView.itemsToDisplay(forItems: items).map {
            ConversationMediaView(mediaCache: mediaCache,
                                  attachment: $0.attachment,
                                  isOutgoing: isOutgoing,
                                  maxMessageWidth: maxMessageWidth)
        }

        super.init(frame: .zero)

        // UIStackView's backgroundColor property has no effect.
        addBackgroundView(withBackgroundColor: Theme.backgroundColor)

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
            let imageSize = (maxMessageWidth - MediaAlbumCellView.kSpacingPts) / 2
            autoSet(viewSize: imageSize, ofViews: itemViews)
            for itemView in itemViews {
                addArrangedSubview(itemView)
            }
            self.axis = .horizontal
            self.spacing = MediaAlbumCellView.kSpacingPts
        case 3:
            //   x
            // X x
            // Big on left, 2 small on right.
            let smallImageSize = (maxMessageWidth - MediaAlbumCellView.kSpacingPts * 2) / 3
            let bigImageSize = smallImageSize * 2 + MediaAlbumCellView.kSpacingPts

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
            self.spacing = MediaAlbumCellView.kSpacingPts
        case 4:
            // X X
            // X X
            // Square
            let imageSize = (maxMessageWidth - MediaAlbumCellView.kSpacingPts) / 2

            let topViews = Array(itemViews[0..<2])
            addArrangedSubview(newRow(rowViews: topViews,
                                      axis: .horizontal,
                                      viewSize: imageSize))

            let bottomViews = Array(itemViews[2..<4])
            addArrangedSubview(newRow(rowViews: bottomViews,
                                      axis: .horizontal,
                                      viewSize: imageSize))

            self.axis = .vertical
            self.spacing = MediaAlbumCellView.kSpacingPts
        default:
            // X X
            // xxx
            // 2 big on top, 3 small on bottom.
            let bigImageSize = (maxMessageWidth - MediaAlbumCellView.kSpacingPts) / 2
            let smallImageSize = (maxMessageWidth - MediaAlbumCellView.kSpacingPts * 2) / 3

            let topViews = Array(itemViews[0..<2])
            addArrangedSubview(newRow(rowViews: topViews,
                                      axis: .horizontal,
                                      viewSize: bigImageSize))

            let bottomViews = Array(itemViews[2..<5])
            addArrangedSubview(newRow(rowViews: bottomViews,
                                      axis: .horizontal,
                                      viewSize: smallImageSize))

            self.axis = .vertical
            self.spacing = MediaAlbumCellView.kSpacingPts

            if items.count > MediaAlbumCellView.kMaxItems {
                guard let lastView = bottomViews.last else {
                    owsFailDebug("Missing lastView")
                    return
                }

                moreItemsView = lastView

                let tintView = UIView()
                tintView.backgroundColor = UIColor(white: 0, alpha: 0.4)
                lastView.addSubview(tintView)
                tintView.autoPinEdgesToSuperviewEdges()

                let moreCount = max(1, items.count - MediaAlbumCellView.kMaxItems)
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

    private func autoSet(viewSize: CGFloat,
                         ofViews views: [ConversationMediaView]) {
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
        stackView.spacing = MediaAlbumCellView.kSpacingPts
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

    private class func itemsToDisplay(forItems items: [ConversationMediaAlbumItem]) -> [ConversationMediaAlbumItem] {
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
                                 items: [ConversationMediaAlbumItem]) -> CGSize {
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

    @objc
    public func mediaView(forLocation location: CGPoint) -> ConversationMediaView? {
        var bestMediaView: ConversationMediaView?
        var bestDistance: CGFloat = 0
        for itemView in itemViews {
            let itemCenter = convert(itemView.center, from: itemView.superview)
            let distance = CGPointDistance(location, itemCenter)
            if bestMediaView != nil && distance > bestDistance {
                continue
            }
            bestMediaView = itemView
            bestDistance = distance
        }
        return bestMediaView
    }

    @objc
    public func isMoreItemsView(mediaView: ConversationMediaView) -> Bool {
        return moreItemsView == mediaView
    }
}
