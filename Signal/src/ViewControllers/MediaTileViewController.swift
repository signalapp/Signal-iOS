//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol MediaTileViewControllerDelegate: class {
    func mediaTileViewController(_ viewController: MediaTileViewController, didTapView tappedView: UIView, mediaGalleryItem: MediaGalleryItem)
}

public class MediaTileViewController: UICollectionViewController, MediaGalleryCellDelegate {

    private weak var mediaGalleryDataSource: MediaGalleryDataSource?

    private var galleryItems: [GalleryDate: [MediaGalleryItem]] {
        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFail("\(logTag) in \(#function) mediaGalleryDataSource was unexpectedly nil")
            return [:]
        }
        return mediaGalleryDataSource.sections
    }
    private var galleryDates: [GalleryDate] {
        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFail("\(logTag) in \(#function) mediaGalleryDataSource was unexpectedly nil")
            return []
        }
        return mediaGalleryDataSource.sectionDates
    }
    public var focusedItem: MediaGalleryItem?

    private let uiDatabaseConnection: YapDatabaseConnection

    public weak var delegate: MediaTileViewControllerDelegate?

    deinit {
        Logger.debug("\(logTag) deinit")
    }

    fileprivate let mediaTileViewLayout: MediaTileViewLayout

    init(mediaGalleryDataSource: MediaGalleryDataSource, uiDatabaseConnection: YapDatabaseConnection) {

        self.mediaGalleryDataSource = mediaGalleryDataSource
        assert(uiDatabaseConnection.isInLongLivedReadTransaction())
        self.uiDatabaseConnection = uiDatabaseConnection

        // Layout Setup

        let screenWidth = UIScreen.main.bounds.size.width
        let kItemsPerRow = 4
        let kInterItemSpacing: CGFloat = 2

        let availableWidth = screenWidth - CGFloat(kItemsPerRow + 1) * kInterItemSpacing
        let kItemWidth = floor(availableWidth / CGFloat(kItemsPerRow))

        let layout: MediaTileViewLayout = MediaTileViewLayout()
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        layout.itemSize = CGSize(width: kItemWidth, height: kItemWidth)
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing
        layout.sectionHeadersPinToVisibleBounds = true
        self.mediaTileViewLayout = layout

        super.init(collectionViewLayout: layout)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: View Lifecycle Overrides

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.title = MediaStrings.allMedia

        guard let collectionView = self.collectionView else {
            owsFail("\(logTag) in \(#function) collectionView was unexpectedly nil")
            return
        }

        collectionView.backgroundColor = UIColor.white

        collectionView.register(MediaGalleryCell.self, forCellWithReuseIdentifier: MediaGalleryCell.reuseIdentifier)
        collectionView.register(MediaGallerySectionHeader.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: MediaGallerySectionHeader.reuseIdentifier)
        collectionView.register(MediaGalleryLoadingHeader.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: MediaGalleryLoadingHeader.reuseIdentifier)

        collectionView.delegate = self

        // TODO iPhoneX
        // feels a bit weird to have content smashed all the way to the bottom edge.
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        self.view.layoutIfNeeded()
        scrollToBottom(animated: false)
    }

    private func indexPath(galleryItem: MediaGalleryItem) -> IndexPath? {
        guard let sectionIdx = galleryDates.index(of: galleryItem.galleryDate) else {
            return nil
        }
        guard let rowIdx = galleryItems[galleryItem.galleryDate]!.index(of: galleryItem) else {
            return nil
        }

        return IndexPath(row: rowIdx, section: sectionIdx + 1)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        guard let focusedItem = self.focusedItem else {
            return
        }

        guard let indexPath = self.indexPath(galleryItem: focusedItem) else {
            owsFail("\(logTag) unexpectedly unable to find indexPath for focusedItem: \(focusedItem)")
            return
        }

        Logger.debug("\(logTag) scrolling to focused item at indexPath: \(indexPath)")
        self.collectionView?.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
    }

    // MARK: UIColletionViewDelegate

    override public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.autoLoadMoreIfNecessary()
    }

    override public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.isUserScrolling = true
    }

    override public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        self.isUserScrolling = false
    }

    private var isUserScrolling: Bool = false {
        didSet {
            autoLoadMoreIfNecessary()
        }
    }

    // MARK: UIColletionViewDataSource

    override public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return galleryItems.keys.count + 2
    }

    override public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        if sectionIdx == kLoadOlderSectionIdx {
            // load older
            return 0
        }

        if sectionIdx == loadNewerSectionIdx {
            // load more recent
            return 0
        }

        guard let sectionDate = self.galleryDates[safe: sectionIdx - 1] else {
            owsFail("\(logTag) in \(#function) unknown section: \(sectionIdx)")
            return 0
        }

        guard let section = self.galleryItems[sectionDate] else {
            owsFail("\(logTag) in \(#function) no section for date: \(sectionDate)")
            return 0
        }

        return section.count
    }

    override public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {

        let defaultView = UICollectionReusableView()
        if (kind == UICollectionElementKindSectionHeader) {
            switch indexPath.section {
            case kLoadOlderSectionIdx:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryLoadingHeader.reuseIdentifier, for: indexPath) as? MediaGalleryLoadingHeader else {

                    owsFail("\(logTag) in \(#function) unable to build section header for kLoadOlderSectionIdx")
                    return defaultView
                }
                let title = NSLocalizedString("GALLERY_TILES_LOADING_OLDER_LABEL", comment: "Label indicating loading is in progress")
                sectionHeader.configure(title: title)
                return sectionHeader
            case loadNewerSectionIdx:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryLoadingHeader.reuseIdentifier, for: indexPath) as? MediaGalleryLoadingHeader else {

                    owsFail("\(logTag) in \(#function) unable to build section header for kLoadOlderSectionIdx")
                    return defaultView
                }
                let title = NSLocalizedString("GALLERY_TILES_LOADING_MORE_RECENT_LABEL", comment: "Label indicating loading is in progress")
                sectionHeader.configure(title: title)
                return sectionHeader
            default:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGallerySectionHeader.reuseIdentifier, for: indexPath) as? MediaGallerySectionHeader else {
                    owsFail("\(logTag) in \(#function) unable to build section header for indexPath: \(indexPath)")
                    return defaultView
                }
                guard let date = self.galleryDates[safe: indexPath.section - 1] else {
                    owsFail("\(logTag) in \(#function) unknown section for indexPath: \(indexPath)")
                    return defaultView
                }

                sectionHeader.configure(title: date.localizedString)
                return sectionHeader
            }
        }

        return defaultView
    }

    override public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        Logger.debug("\(logTag) in \(#function) indexPath: \(indexPath)")

        let defaultCell = UICollectionViewCell()

        switch indexPath.section {
        case kLoadOlderSectionIdx:
            owsFail("\(logTag) in \(#function) unexpected cell for kLoadOlderSectionIdx")
            return defaultCell
        case loadNewerSectionIdx:
            owsFail("\(logTag) in \(#function) unexpected cell for loadNewerSectionIdx")
            return defaultCell
        default:
            guard let sectionDate = self.galleryDates[safe: indexPath.section - 1] else {
                owsFail("\(logTag) in \(#function) unknown section: \(indexPath.section)")
                return defaultCell
            }

            guard let sectionItems = self.galleryItems[sectionDate] else {
                owsFail("\(logTag) in \(#function) no section for date: \(sectionDate)")
                return defaultCell
            }

            guard let galleryItem = sectionItems[safe: indexPath.row] else {
                owsFail("\(logTag) in \(#function) no message for row: \(indexPath.row)")
                return defaultCell
            }

            guard let cell = self.collectionView?.dequeueReusableCell(withReuseIdentifier: MediaGalleryCell.reuseIdentifier, for: indexPath) as? MediaGalleryCell else {
                owsFail("\(logTag) in \(#function) unexpected cell for indexPath: \(indexPath)")
                return defaultCell
            }

            cell.configure(item: galleryItem, delegate: self)

            return cell
        }
    }

    // MARK: UICollectionViewDelegateFlowLayout

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               referenceSizeForHeaderInSection section: Int) -> CGSize {

        let kHeaderHeight: CGFloat = 50

        switch section {
        case kLoadOlderSectionIdx:
            // Show "loading older..." iff there is still older data to be fetched
            guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
                owsFail("\(logTag) in \(#function) mediaGalleryDataSource was unexpectedly nil")
                return CGSize.zero
            }
            return mediaGalleryDataSource.hasFetchedOldest ? CGSize.zero : CGSize(width: 0, height: 100)
        case loadNewerSectionIdx:
            // Show "loading newer..." iff there is still more recent data to be fetched
            guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
                owsFail("\(logTag) in \(#function) mediaGalleryDataSource was unexpectedly nil")
                return CGSize.zero
            }
            return mediaGalleryDataSource.hasFetchedMostRecent ? CGSize.zero : CGSize(width: 0, height: 100)
        default:
            return CGSize(width: 0, height: kHeaderHeight)
        }
    }
    // MARK: MediaGalleryDelegate

    fileprivate func didTapCell(_ cell: MediaGalleryCell, item: MediaGalleryItem) {
        Logger.debug("\(logTag) in \(#function)")
        self.delegate?.mediaTileViewController(self, didTapView: cell.imageView, mediaGalleryItem: item)
    }

    // MARK: Lazy Loading

    // This should be substantially larger than one screen size so we don't have to call it
    // multiple times in a rapid succession, but not so large that loading get's really chopping
    let kMediaTileViewLoadBatchSize: UInt = 40
    var oldestLoadedItem: MediaGalleryItem? {
        guard let oldestDate = galleryDates.first else {
            return nil
        }

        return galleryItems[oldestDate]?.first
    }

    var mostRecentLoadedItem: MediaGalleryItem? {
        guard let mostRecentDate = galleryDates.last else {
            return nil
        }

        return galleryItems[mostRecentDate]?.last
    }

    var isFetchingMoreData: Bool = false

    let kLoadOlderSectionIdx = 0
    var loadNewerSectionIdx: Int {
        return galleryDates.count + 1
    }

    public func autoLoadMoreIfNecessary() {
        let kEdgeThreshold: CGFloat = 800

        if (self.isUserScrolling) {
            return
        }

        guard let collectionView = self.collectionView else {
            owsFail("\(logTag) in \(#function) collectionView was unexpectedly nil")
            return
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFail("\(logTag) in \(#function) mediaGalleryDataSource was unexpectedly nil")
            return
        }

        let contentOffsetY = collectionView.contentOffset.y
        let oldContentHeight = collectionView.contentSize.height

        if contentOffsetY < kEdgeThreshold {
            // Near the top, load older content

            guard let oldestLoadedItem = self.oldestLoadedItem else {
                Logger.debug("\(logTag) in \(#function) no oldest item")
                return
            }

            guard !mediaGalleryDataSource.hasFetchedOldest else {
                return
            }

            guard !isFetchingMoreData else {
                Logger.debug("\(logTag) in \(#function) already fetching more data")
                return
            }
            isFetchingMoreData = true

            CATransaction.begin()
            CATransaction.setDisableActions(true)

            // mediaTileViewLayout will adjust content offset to compensate for the change in content height so that
            // the same content is visible after the update. I considered doing something like setContentOffset in the
            // batchUpdate completion block, but it caused a distinct flicker, which I was able to avoid with the
            // `CollectionViewLayout.prepare` based approach.
            mediaTileViewLayout.isInsertingCellsToTop = true
            mediaTileViewLayout.contentSizeBeforeInsertingToTop = collectionView.contentSize
            collectionView.performBatchUpdates({
                mediaGalleryDataSource.ensureGalleryItemsLoaded(.before, item: oldestLoadedItem, amount: self.kMediaTileViewLoadBatchSize) { addedSections, addedItems in
                    Logger.debug("\(self.logTag) in \(#function) insertingSections: \(addedSections) items: \(addedItems)")

                    collectionView.insertSections(addedSections)
                    collectionView.insertItems(at: addedItems)
                }
            }, completion: { finished in
                Logger.debug("\(self.logTag) in \(#function) performBatchUpdates finished: \(finished)")
                self.isFetchingMoreData = false
                CATransaction.commit()
            })

        } else if oldContentHeight - contentOffsetY < kEdgeThreshold {
            // Near the bottom, load newer content

            guard let mostRecentLoadedItem = self.mostRecentLoadedItem else {
                Logger.debug("\(logTag) in \(#function) no mostRecent item")
                return
            }

            guard !mediaGalleryDataSource.hasFetchedMostRecent else {
                return
            }

            guard !isFetchingMoreData else {
                Logger.debug("\(logTag) in \(#function) already fetching more data")
                return
            }
            isFetchingMoreData = true

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                collectionView.performBatchUpdates({
                    mediaGalleryDataSource.ensureGalleryItemsLoaded(.after, item: mostRecentLoadedItem, amount: self.kMediaTileViewLoadBatchSize) { addedSections, addedItems in
                        Logger.debug("\(self.logTag) in \(#function) insertingSections: \(addedSections), items: \(addedItems)")
                        collectionView.insertSections(addedSections)
                        collectionView.insertItems(at: addedItems)
                    }
                }, completion: { finished in
                    Logger.debug("\(self.logTag) in \(#function) performBatchUpdates finished: \(finished)")
                    self.isFetchingMoreData = false
                    CATransaction.commit()
                })
            }
        }
    }

    // MARK: Util

    private func scrollToBottom(animated isAnimated: Bool) {
        guard let collectionView = self.collectionView else {
            owsFail("\(self.logTag) in \(#function) collectionView was unexpectedly nil")
            return
        }

        let yOffset: CGFloat = collectionView.contentSize.height - collectionView.bounds.size.height + collectionView.contentInset.bottom
        let offset: CGPoint  = CGPoint(x: 0, y: yOffset)

        collectionView.setContentOffset(offset, animated: isAnimated)
    }
}

// MARK: - Private Helper Classes

// Accomodates remaining scrolled to the same "apparent" position when new content is insterted
// into the top of a collectionView. There are multiple ways to solve this problem, but this
// is the only one which avoided a perceptible flicker.
fileprivate class MediaTileViewLayout: UICollectionViewFlowLayout {

    fileprivate var isInsertingCellsToTop: Bool = false
    fileprivate var contentSizeBeforeInsertingToTop: CGSize?

    override public func prepare() {
        super.prepare()

        if isInsertingCellsToTop {
            if let collectionView = collectionView, let oldContentSize = contentSizeBeforeInsertingToTop {
                let newContentSize = collectionViewContentSize
                let contentOffsetY = collectionView.contentOffset.y + (newContentSize.height - oldContentSize.height)
                let newOffset = CGPoint(x: collectionView.contentOffset.x, y: contentOffsetY)
                collectionView.setContentOffset(newOffset, animated: false)
            }
            contentSizeBeforeInsertingToTop = nil
            isInsertingCellsToTop = false
        }
    }
}

fileprivate class MediaGallerySectionHeader: UICollectionReusableView {

    static let reuseIdentifier = "MediaGallerySectionHeader"

    // HACK: scrollbar incorrectly appears *behind* section headers
    // in collection view on iOS11 =(
    private class AlwaysOnTopLayer: CALayer {
        override var zPosition: CGFloat {
            get { return 0 }
            set {}
        }
    }

    let label: UILabel

    override class var layerClass: AnyClass {
        get {
            // HACK: scrollbar incorrectly appears *behind* section headers
            // in collection view on iOS11 =(
            if #available(iOS 11, *) {
                return AlwaysOnTopLayer.self
            } else {
                return super.layerClass
            }
        }
    }

    override init(frame: CGRect) {
        label = UILabel()

        let blurEffect = UIBlurEffect(style: .extraLight)
        let blurEffectView = UIVisualEffectView(effect: blurEffect)

        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        super.init(frame: frame)

        self.addSubview(blurEffectView)
        self.addSubview(label)

        blurEffectView.autoPinEdgesToSuperviewEdges()
        label.autoPinEdge(toSuperviewEdge: .trailing)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: 10)
        label.autoVCenterInSuperview()
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(title: String) {
        self.label.text = title
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        self.label.text = nil
    }
}

fileprivate protocol MediaGalleryCellDelegate: class {
    func didTapCell(_ cell: MediaGalleryCell, item: MediaGalleryItem)
}

fileprivate class MediaGalleryLoadingHeader: UICollectionViewCell {

    static let reuseIdentifier = "MediaGalleryLoadingHeader"

    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        // TODO add spinnner, start/stop animating on will/end display
        addSubview(label)

        label.autoCenterInSuperview()
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(title: String) {
        self.label.text = title
    }

    public override func prepareForReuse() {
        self.label.text = nil
    }
}

fileprivate class MediaGalleryCell: UICollectionViewCell {

    static let reuseIdentifier = "MediaGalleryCell"

    public let imageView: UIImageView
    private var tapGesture: UITapGestureRecognizer!

    private let badgeView: UIImageView
    private let gradientView: GradientView

    private var item: MediaGalleryItem?
    public weak var delegate: MediaGalleryCellDelegate?

    static let videoBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_video")
    static let animatedBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_gif")

    override init(frame: CGRect) {
        self.imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        self.badgeView = UIImageView()
        badgeView.isHidden = true

        self.gradientView = GradientView(from: .clear, to: UIColor.black.withAlphaComponent(0.5))

        super.init(frame: frame)

        self.tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        self.addGestureRecognizer(tapGesture)

        self.clipsToBounds = true
        self.contentView.addSubview(imageView)
        self.contentView.addSubview(gradientView)
        self.contentView.addSubview(badgeView)

        imageView.autoPinEdgesToSuperviewEdges()

        gradientView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .top)
        gradientView.autoSetDimension(.height, toSize: 16)

        // Note assets were rendered to match exactly. We don't want to re-size with
        // content mode lest they become less legible.
        let kBadgeSize = CGSize(width: 18, height: 12)
        badgeView.autoPinEdge(toSuperviewEdge: .leading, withInset: 3)
        badgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)
        badgeView.autoSetDimensions(to: kBadgeSize)
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(item: MediaGalleryItem, delegate: MediaGalleryCellDelegate) {
        self.item = item
        self.imageView.image = item.thumbnailImage
        if item.isVideo {
            self.gradientView.isHidden = false
            self.badgeView.isHidden = false
            self.badgeView.image = MediaGalleryCell.videoBadgeImage
        } else if item.isAnimated {
            self.gradientView.isHidden = false
            self.badgeView.isHidden = false
            self.badgeView.image = MediaGalleryCell.animatedBadgeImage
        } else {
            assert(item.isImage)
            self.gradientView.isHidden = true
            self.badgeView.isHidden = true
        }

        self.delegate = delegate
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        self.item = nil
        self.imageView.image = nil
        self.badgeView.isHidden = true
        self.delegate = nil
    }

    // MARK: Events

    func didTap(gestureRecognizer: UITapGestureRecognizer) {
        guard let item = self.item else {
            owsFail("\(logTag) item was unexpectedly nil")
            return
        }

        self.delegate?.didTapCell(self, item: item)
    }
}
