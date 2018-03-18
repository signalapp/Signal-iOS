//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol MediaTileViewControllerDelegate: class {
    func mediaTileViewController(_ viewController: MediaTileViewController, didTapMediaGalleryItem mediaGalleryItem: MediaGalleryItem)
}

public class MediaTileViewController: UICollectionViewController, MediaGalleryCellDelegate {

    // TODO weak?
    private var mediaGalleryDataSource: MediaGalleryDataSource

    private var galleryItems: [GalleryDate: [MediaGalleryItem]] {
        return mediaGalleryDataSource.sections
    }
    private var galleryDates: [GalleryDate] {
        return mediaGalleryDataSource.sectionDates
    }

    private let uiDatabaseConnection: YapDatabaseConnection

    public weak var delegate: MediaTileViewControllerDelegate?

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

        let layout: UICollectionViewFlowLayout = UICollectionViewFlowLayout()
        layout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        layout.itemSize = CGSize(width: kItemWidth, height: kItemWidth)
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing
        layout.sectionHeadersPinToVisibleBounds = true

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

        if sectionIdx == kLoadNewerSectionIdx {
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
                // TODO localize
                sectionHeader.configure(title: "Loading older...")
                return sectionHeader
            case kLoadNewerSectionIdx:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryLoadingHeader.reuseIdentifier, for: indexPath) as? MediaGalleryLoadingHeader else {

                    owsFail("\(logTag) in \(#function) unable to build section header for kLoadOlderSectionIdx")
                    return defaultView
                }
                // TODO localize
                sectionHeader.configure(title: "Loading newer...")
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
        case kLoadNewerSectionIdx:
            owsFail("\(logTag) in \(#function) unexpected cell for kLoadNewerSectionIdx")
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
            return self.mediaGalleryDataSource.hasFetchedOldest ? CGSize.zero : CGSize(width: 0, height: 100)
        case kLoadNewerSectionIdx:
            // Show "loading newer..." iff there is still more recent data to be fetched
            return self.mediaGalleryDataSource.hasFetchedMostRecent ? CGSize.zero : CGSize(width: 0, height: 100)
        default:
            return CGSize(width: 0, height: kHeaderHeight)
        }
    }
    // MARK: MediaGalleryDelegate

    public func didTapCell(_ cell: MediaGalleryCell, item: MediaGalleryItem) {
        Logger.debug("\(logTag) in \(#function)")
        self.delegate?.mediaTileViewController(self, didTapMediaGalleryItem: item)
    }

    // MARK: Lazy Loading

    // This should be substantially larger than one screen size so we don't have to call it
    // multiple times in a rapid succession.
    let kMediaTileViewLoadBatchSize: UInt = 200
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
    var kLoadNewerSectionIdx: Int {
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

        let contentOffsetY = collectionView.contentOffset.y
        let oldContentHeight = collectionView.contentSize.height

        if contentOffsetY < kEdgeThreshold {
            // Near the top, load older content

            guard let oldestLoadedItem = self.oldestLoadedItem else {
                Logger.debug("\(logTag) in \(#function) no oldest item")
                return
            }

            guard !isFetchingMoreData else {
                Logger.debug("\(logTag) in \(#function) already fetching more data")
                return
            }

            isFetchingMoreData = true

            let scrollDistanceToBottom = oldContentHeight - contentOffsetY

            collectionView.performBatchUpdates({
                self.mediaGalleryDataSource.ensureGalleryItemsLoaded(.before, item: oldestLoadedItem, amount: self.kMediaTileViewLoadBatchSize) { addedSections, addedItems in
                    Logger.debug("\(self.logTag) in \(#function) insertingSections: \(addedSections) items: \(addedItems)")

                    collectionView.insertSections(addedSections)
                    collectionView.insertItems(at: addedItems)
                }
            }, completion: { finished in

                // Adjust content offset to affect change in content height so that the same content is visible after
                // the update.
                let newContentOffset = CGPoint(x: 0, y: collectionView.contentSize.height - scrollDistanceToBottom)
                collectionView.setContentOffset(newContentOffset, animated: false)

                Logger.debug("\(self.logTag) in \(#function) performBatchUpdates finished: \(finished)")
                self.isFetchingMoreData = false
            })
        } else if oldContentHeight - contentOffsetY < kEdgeThreshold {
            // Near the bottom, load newer content

            guard let mostRecentLoadedItem = self.mostRecentLoadedItem else {
                Logger.debug("\(logTag) in \(#function) no mostRecent item")
                return
            }

            guard !isFetchingMoreData else {
                Logger.debug("\(logTag) in \(#function) already fetching more data")
                return
            }

            isFetchingMoreData = true
            collectionView.performBatchUpdates({
                self.mediaGalleryDataSource.ensureGalleryItemsLoaded(.after, item: mostRecentLoadedItem, amount: self.kMediaTileViewLoadBatchSize) { addedSections, addedItems in
                    guard let collectionView = self.collectionView else {
                        Logger.debug("\(self.logTag) in \(#function) collectionView was unexpectedly nil")
                        return
                    }
                    Logger.debug("\(self.logTag) in \(#function) insertingSections: \(addedSections), items: \(addedItems)")

                    collectionView.insertSections(addedSections)
                    collectionView.insertItems(at: addedItems)
                }
            }, completion: { finished in
                Logger.debug("\(self.logTag) in \(#function) performBatchUpdates finished: \(finished)")
                self.isFetchingMoreData = false
            })
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

class MediaGallerySectionHeader: UICollectionReusableView {

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

        let blurEffect = UIBlurEffect(style: .light)
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

public protocol MediaGalleryCellDelegate: class {
    func didTapCell(_ cell: MediaGalleryCell, item: MediaGalleryItem)
}

public class MediaGalleryLoadingHeader: UICollectionViewCell {

    static let reuseIdentifier = "MediaGalleryLoadingHeader"

    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        // TODO add spinnner, start/stop animating on will/end display
        self.backgroundColor = UIColor.green
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

public class MediaGalleryCell: UICollectionViewCell {

    static let reuseIdentifier = "MediaGalleryCell"

    private let imageView: UIImageView
    private var tapGesture: UITapGestureRecognizer!

    private var item: MediaGalleryItem?
    public weak var delegate: MediaGalleryCellDelegate?

    override init(frame: CGRect) {
        self.imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        super.init(frame: frame)

        self.tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap))
        self.addGestureRecognizer(tapGesture)

        self.clipsToBounds = true
        self.addSubview(imageView)

        imageView.autoPinEdgesToSuperviewEdges()
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(item: MediaGalleryItem, delegate: MediaGalleryCellDelegate) {
        self.item = item
        self.imageView.image = item.image
        self.delegate = delegate
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        self.item = nil
        self.imageView.image = nil
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
