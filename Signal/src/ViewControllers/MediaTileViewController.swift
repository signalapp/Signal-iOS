//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol MediaTileViewControllerDelegate: class {
    func mediaTileViewController(_ viewController: MediaTileViewController, didTapView tappedView: UIView, mediaGalleryItem: MediaGalleryItem)
}

public class MediaTileViewController: UICollectionViewController, MediaGalleryDataSourceDelegate, UICollectionViewDelegateFlowLayout {

    private weak var mediaGalleryDataSource: MediaGalleryDataSource?

    private var galleryItems: [GalleryDate: [MediaGalleryItem]] {
        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return [:]
        }
        return mediaGalleryDataSource.sections
    }
    private var galleryDates: [GalleryDate] {
        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return []
        }
        return mediaGalleryDataSource.sectionDates
    }
    public var focusedItem: MediaGalleryItem?

    private let uiDatabaseConnection: YapDatabaseConnection

    public weak var delegate: MediaTileViewControllerDelegate?

    deinit {
        Logger.debug("deinit")
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
        notImplemented()
    }

    // MARK: View Lifecycle Overrides

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.title = MediaStrings.allMedia

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        collectionView.backgroundColor = Theme.backgroundColor

        collectionView.register(MediaGalleryCell.self, forCellWithReuseIdentifier: MediaGalleryCell.reuseIdentifier)
        collectionView.register(MediaGallerySectionHeader.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: MediaGallerySectionHeader.reuseIdentifier)
        collectionView.register(MediaGalleryStaticHeader.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier)

        collectionView.delegate = self

        // feels a bit weird to have content smashed all the way to the bottom edge.
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        let footerBar = UIToolbar()
        self.footerBar = footerBar
        let deleteButton = UIBarButtonItem(barButtonSystemItem: .trash,
                                          target: self,
                                          action: #selector(didPressDelete))
        self.deleteButton =  deleteButton
        let footerItems = [
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
            deleteButton,
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        ]
        footerBar.setItems(footerItems, animated: false)

        self.view.addSubview(self.footerBar)
        footerBar.autoPinWidthToSuperview()
        footerBar.autoSetDimension(.height, toSize: kFooterBarHeight)
        self.footerBarBottomConstraint = footerBar.autoPinEdge(toSuperviewEdge: .bottom, withInset: -kFooterBarHeight)

        updateSelectButton()
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
            owsFailDebug("unexpectedly unable to find indexPath for focusedItem: \(focusedItem)")
            return
        }

        Logger.debug("scrolling to focused item at indexPath: \(indexPath)")
        self.view.layoutIfNeeded()
        self.collectionView?.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        self.autoLoadMoreIfNecessary()
    }

    // MARK: UICollectionViewDelegate

    override public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.autoLoadMoreIfNecessary()
    }

    override public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.isUserScrolling = true
    }

    override public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        self.isUserScrolling = false
    }

    override public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {

        Logger.debug("")

        guard galleryDates.count > 0 else {
            return false
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx, loadNewerSectionIdx:
            return false
        default:
            return true
        }
    }

    override public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {

        Logger.debug("")

        guard galleryDates.count > 0 else {
            return false
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx, loadNewerSectionIdx:
            return false
        default:
            return true
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {

        Logger.debug("")

        guard galleryDates.count > 0 else {
            return false
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx, loadNewerSectionIdx:
            return false
        default:
            return true
        }
    }

    override public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.debug("")

        guard let galleryCell = self.collectionView(collectionView, cellForItemAt: indexPath) as? MediaGalleryCell else {
            owsFailDebug("galleryCell was unexpectedly nil")
            return
        }

        guard let galleryItem = galleryCell.item else {
            owsFailDebug("galleryItem was unexpectedly nil")
            return
        }

        if isInBatchSelectMode {
            updateDeleteButton()
        } else {
            collectionView.deselectItem(at: indexPath, animated: true)
            self.delegate?.mediaTileViewController(self, didTapView: galleryCell.imageView, mediaGalleryItem: galleryItem)
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        Logger.debug("")

        if isInBatchSelectMode {
            updateDeleteButton()
        }
    }

    private var isUserScrolling: Bool = false {
        didSet {
            autoLoadMoreIfNecessary()
        }
    }

    // MARK: UICollectionViewDataSource

    override public func numberOfSections(in collectionView: UICollectionView) -> Int {
        guard galleryDates.count > 0 else {
            // empty gallery
            return 1
        }

        // One for each galleryDate plus a "loading older" and "loading newer" section
        return galleryItems.keys.count + 2
    }

    override public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {

        guard galleryDates.count > 0 else {
            // empty gallery
            return 0
        }

        if sectionIdx == kLoadOlderSectionIdx {
            // load older
            return 0
        }

        if sectionIdx == loadNewerSectionIdx {
            // load more recent
            return 0
        }

        guard let sectionDate = self.galleryDates[safe: sectionIdx - 1] else {
            owsFailDebug("unknown section: \(sectionIdx)")
            return 0
        }

        guard let section = self.galleryItems[sectionDate] else {
            owsFailDebug("no section for date: \(sectionDate)")
            return 0
        }

        return section.count
    }

    override public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {

        let defaultView = UICollectionReusableView()

        guard galleryDates.count > 0 else {
            guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier, for: indexPath) as? MediaGalleryStaticHeader else {

                owsFailDebug("unable to build section header for kLoadOlderSectionIdx")
                return defaultView
            }
            let title = NSLocalizedString("GALLERY_TILES_EMPTY_GALLERY", comment: "Label indicating media gallery is empty")
            sectionHeader.configure(title: title)
            return sectionHeader
        }

        if (kind == UICollectionElementKindSectionHeader) {
            switch indexPath.section {
            case kLoadOlderSectionIdx:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier, for: indexPath) as? MediaGalleryStaticHeader else {

                    owsFailDebug("unable to build section header for kLoadOlderSectionIdx")
                    return defaultView
                }
                let title = NSLocalizedString("GALLERY_TILES_LOADING_OLDER_LABEL", comment: "Label indicating loading is in progress")
                sectionHeader.configure(title: title)
                return sectionHeader
            case loadNewerSectionIdx:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier, for: indexPath) as? MediaGalleryStaticHeader else {

                    owsFailDebug("unable to build section header for kLoadOlderSectionIdx")
                    return defaultView
                }
                let title = NSLocalizedString("GALLERY_TILES_LOADING_MORE_RECENT_LABEL", comment: "Label indicating loading is in progress")
                sectionHeader.configure(title: title)
                return sectionHeader
            default:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGallerySectionHeader.reuseIdentifier, for: indexPath) as? MediaGallerySectionHeader else {
                    owsFailDebug("unable to build section header for indexPath: \(indexPath)")
                    return defaultView
                }
                guard let date = self.galleryDates[safe: indexPath.section - 1] else {
                    owsFailDebug("unknown section for indexPath: \(indexPath)")
                    return defaultView
                }

                sectionHeader.configure(title: date.localizedString)
                return sectionHeader
            }
        }

        return defaultView
    }

    override public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        Logger.debug("indexPath: \(indexPath)")

        let defaultCell = UICollectionViewCell()

        guard galleryDates.count > 0 else {
            owsFailDebug("unexpected cell for loadNewerSectionIdx")
            return defaultCell
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx:
            owsFailDebug("unexpected cell for kLoadOlderSectionIdx")
            return defaultCell
        case loadNewerSectionIdx:
            owsFailDebug("unexpected cell for loadNewerSectionIdx")
            return defaultCell
        default:
            guard let galleryItem = galleryItem(at: indexPath) else {
                owsFailDebug("no message for path: \(indexPath)")
                return defaultCell
            }

            guard let cell = self.collectionView?.dequeueReusableCell(withReuseIdentifier: MediaGalleryCell.reuseIdentifier, for: indexPath) as? MediaGalleryCell else {
                owsFailDebug("unexpected cell for indexPath: \(indexPath)")
                return defaultCell
            }

            cell.configure(item: galleryItem)

            return cell
        }
    }

    func galleryItem(at indexPath: IndexPath) -> MediaGalleryItem? {
        guard let sectionDate = self.galleryDates[safe: indexPath.section - 1] else {
            owsFailDebug("unknown section: \(indexPath.section)")
            return nil
        }

        guard let sectionItems = self.galleryItems[sectionDate] else {
            owsFailDebug("no section for date: \(sectionDate)")
            return nil
        }

        guard let galleryItem = sectionItems[safe: indexPath.row] else {
            owsFailDebug("no message for row: \(indexPath.row)")
            return nil
        }

        return galleryItem
    }

    // MARK: UICollectionViewDelegateFlowLayout

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               referenceSizeForHeaderInSection section: Int) -> CGSize {

        let kMonthHeaderSize: CGSize = CGSize(width: 0, height: 50)
        let kStaticHeaderSize: CGSize = CGSize(width: 0, height: 100)

        guard galleryDates.count > 0 else {
            return kStaticHeaderSize
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return CGSize.zero
        }

        switch section {
        case kLoadOlderSectionIdx:
            // Show "loading older..." iff there is still older data to be fetched
            return mediaGalleryDataSource.hasFetchedOldest ? CGSize.zero : kStaticHeaderSize
        case loadNewerSectionIdx:
            // Show "loading newer..." iff there is still more recent data to be fetched
            return mediaGalleryDataSource.hasFetchedMostRecent ? CGSize.zero : kStaticHeaderSize
        default:
            return kMonthHeaderSize
        }
    }

    // MARK: Batch Selection

    var isInBatchSelectMode = false {
        didSet {
            collectionView!.allowsMultipleSelection = isInBatchSelectMode
            updateSelectButton()
            updateDeleteButton()
        }
    }

    func updateDeleteButton() {
        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        if let count = collectionView.indexPathsForSelectedItems?.count, count > 0 {
            self.deleteButton.isEnabled = true
        } else {
            self.deleteButton.isEnabled = false
        }
    }

    func updateSelectButton() {
        if isInBatchSelectMode {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(didCancelSelect))
        } else {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("BUTTON_SELECT", comment: "Button text to enable batch selection mode"),
                                                                     style: .plain,
                                                                     target: self,
                                                                     action: #selector(didTapSelect))
        }
    }

    @objc
    func didTapSelect(_ sender: Any) {
        isInBatchSelectMode = true

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        // show toolbar
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut, animations: {
            NSLayoutConstraint.deactivate([self.footerBarBottomConstraint])
            self.footerBarBottomConstraint = self.footerBar.autoPin(toBottomLayoutGuideOf: self, withInset: 0)

            self.footerBar.superview?.layoutIfNeeded()

            // ensure toolbar doesn't cover bottom row.
            collectionView.contentInset.bottom += self.kFooterBarHeight
        }, completion: nil)

        // disabled until at least one item is selected
        self.deleteButton.isEnabled = false

        // Don't allow the user to leave mid-selection, so they realized they have
        // to cancel (lose) their selection if they leave.
        self.navigationItem.hidesBackButton = true
    }

    @objc
    func didCancelSelect(_ sender: Any) {
        endSelectMode()
    }

    func endSelectMode() {
        isInBatchSelectMode = false

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        // hide toolbar
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut, animations: {
            NSLayoutConstraint.deactivate([self.footerBarBottomConstraint])
            self.footerBarBottomConstraint = self.footerBar.autoPinEdge(toSuperviewEdge: .bottom, withInset: -self.kFooterBarHeight)
            self.footerBar.superview?.layoutIfNeeded()

            // undo "ensure toolbar doesn't cover bottom row."
            collectionView.contentInset.bottom -= self.kFooterBarHeight
        }, completion: nil)

        self.navigationItem.hidesBackButton = false

        // deselect any selected
        collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false)}
    }

    @objc
    func didPressDelete(_ sender: Any) {
        Logger.debug("")

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        guard let indexPaths = collectionView.indexPathsForSelectedItems else {
            owsFailDebug("indexPaths was unexpectedly nil")
            return
        }

        let items: [MediaGalleryItem] = indexPaths.compactMap { return self.galleryItem(at: $0) }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return
        }

        let confirmationTitle: String = {
            if indexPaths.count == 1 {
                return NSLocalizedString("MEDIA_GALLERY_DELETE_SINGLE_MESSAGE", comment: "Confirmation button text to delete selected media message from the gallery")
            } else {
                let format = NSLocalizedString("MEDIA_GALLERY_DELETE_MULTIPLE_MESSAGES_FORMAT", comment: "Confirmation button text to delete selected media from the gallery, embeds {{number of messages}}")
                return String(format: format, indexPaths.count)
            }
        }()

        let deleteAction = UIAlertAction(title: confirmationTitle, style: .destructive) { _ in
            mediaGalleryDataSource.delete(items: items, initiatedBy: self)
            self.endSelectMode()
        }

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(deleteAction)
        actionSheet.addAction(OWSAlerts.cancelAction)

        present(actionSheet, animated: true)
    }

    var footerBar: UIToolbar!
    var deleteButton: UIBarButtonItem!
    var footerBarBottomConstraint: NSLayoutConstraint!
    let kFooterBarHeight: CGFloat = 40

    // MARK: MediaGalleryDataSourceDelegate

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, willDelete items: [MediaGalleryItem], initiatedBy: MediaGalleryDataSourceDelegate) {
        Logger.debug("")

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        // We've got to lay out the collectionView before any changes are made to the date source
        // otherwise we'll fail when we try to remove the deleted sections/rows
        collectionView.layoutIfNeeded()
    }

    func mediaGalleryDataSource(_ mediaGalleryDataSource: MediaGalleryDataSource, deletedSections: IndexSet, deletedItems: [IndexPath]) {
        Logger.debug("with deletedSections: \(deletedSections) deletedItems: \(deletedItems)")

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpetedly nil")
            return
        }

        guard mediaGalleryDataSource.galleryItemCount > 0  else {
            // Show Empty
            self.collectionView?.reloadData()
            return
        }

        collectionView.performBatchUpdates({
            collectionView.deleteSections(deletedSections)
            collectionView.deleteItems(at: deletedItems)
        })
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
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        guard let mediaGalleryDataSource = self.mediaGalleryDataSource else {
            owsFailDebug("mediaGalleryDataSource was unexpectedly nil")
            return
        }

        let contentOffsetY = collectionView.contentOffset.y
        let oldContentHeight = collectionView.contentSize.height

        if contentOffsetY < kEdgeThreshold {
            // Near the top, load older content

            guard let oldestLoadedItem = self.oldestLoadedItem else {
                Logger.debug("no oldest item")
                return
            }

            guard !mediaGalleryDataSource.hasFetchedOldest else {
                return
            }

            guard !isFetchingMoreData else {
                Logger.debug("already fetching more data")
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
                    Logger.debug("insertingSections: \(addedSections) items: \(addedItems)")

                    collectionView.insertSections(addedSections)
                    collectionView.insertItems(at: addedItems)
                }
            }, completion: { finished in
                Logger.debug("performBatchUpdates finished: \(finished)")
                self.isFetchingMoreData = false
                CATransaction.commit()
            })

        } else if oldContentHeight - contentOffsetY < kEdgeThreshold {
            // Near the bottom, load newer content

            guard let mostRecentLoadedItem = self.mostRecentLoadedItem else {
                Logger.debug("no mostRecent item")
                return
            }

            guard !mediaGalleryDataSource.hasFetchedMostRecent else {
                return
            }

            guard !isFetchingMoreData else {
                Logger.debug("already fetching more data")
                return
            }
            isFetchingMoreData = true

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            UIView.performWithoutAnimation {
                collectionView.performBatchUpdates({
                    mediaGalleryDataSource.ensureGalleryItemsLoaded(.after, item: mostRecentLoadedItem, amount: self.kMediaTileViewLoadBatchSize) { addedSections, addedItems in
                        Logger.debug("insertingSections: \(addedSections), items: \(addedItems)")
                        collectionView.insertSections(addedSections)
                        collectionView.insertItems(at: addedItems)
                    }
                }, completion: { finished in
                    Logger.debug("performBatchUpdates finished: \(finished)")
                    self.isFetchingMoreData = false
                    CATransaction.commit()
                })
            }
        }
    }
}

// MARK: - Private Helper Classes

// Accomodates remaining scrolled to the same "apparent" position when new content is insterted
// into the top of a collectionView. There are multiple ways to solve this problem, but this
// is the only one which avoided a perceptible flicker.
private class MediaTileViewLayout: UICollectionViewFlowLayout {

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

private class MediaGallerySectionHeader: UICollectionReusableView {

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
        label.textColor = Theme.primaryColor

        let blurEffect = Theme.barBlurEffect
        let blurEffectView = UIVisualEffectView(effect: blurEffect)

        blurEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        super.init(frame: frame)

        self.backgroundColor = Theme.navbarBackgroundColor.withAlphaComponent(OWSNavigationBar.backgroundBlurMutingFactor)

        self.addSubview(blurEffectView)
        self.addSubview(label)

        blurEffectView.autoPinEdgesToSuperviewEdges()
        label.autoPinEdge(toSuperviewEdge: .trailing)
        label.autoPinEdge(toSuperviewEdge: .leading, withInset: 10)
        label.autoVCenterInSuperview()
    }

    @available(*, unavailable, message: "Unimplemented")
    required init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public func configure(title: String) {
        self.label.text = title
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        self.label.text = nil
    }
}

private class MediaGalleryStaticHeader: UICollectionViewCell {

    static let reuseIdentifier = "MediaGalleryStaticHeader"

    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(label)

        label.textColor = Theme.primaryColor
        label.textAlignment = .center
        label.numberOfLines = 0
        label.autoPinEdgesToSuperviewMargins()
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public func configure(title: String) {
        self.label.text = title
    }

    public override func prepareForReuse() {
        self.label.text = nil
    }
}

private class MediaGalleryCell: UICollectionViewCell {

    static let reuseIdentifier = "MediaGalleryCell"

    public let imageView: UIImageView

    private let contentTypeBadgeView: UIImageView
    private let selectedBadgeView: UIImageView

    private let highlightedView: UIView
    private let selectedView: UIView

    fileprivate var item: MediaGalleryItem?

    static let videoBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_video")
    static let animatedBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_gif")
    static let selectedBadgeImage = #imageLiteral(resourceName: "selected_blue_circle")

    override var isSelected: Bool {
        didSet {
            self.selectedBadgeView.isHidden = !self.isSelected
            self.selectedView.isHidden = !self.isSelected
        }
    }

    override var isHighlighted: Bool {
        didSet {
            self.highlightedView.isHidden = !self.isHighlighted
        }
    }

    override init(frame: CGRect) {
        self.imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        self.contentTypeBadgeView = UIImageView()
        contentTypeBadgeView.isHidden = true

        self.selectedBadgeView = UIImageView()
        selectedBadgeView.image = MediaGalleryCell.selectedBadgeImage
        selectedBadgeView.isHidden = true

        self.highlightedView = UIView()
        highlightedView.alpha = 0.2
        highlightedView.backgroundColor = Theme.primaryColor
        highlightedView.isHidden = true

        self.selectedView = UIView()
        selectedView.alpha = 0.3
        selectedView.backgroundColor = Theme.backgroundColor
        selectedView.isHidden = true

        super.init(frame: frame)

        self.clipsToBounds = true

        self.contentView.addSubview(imageView)
        self.contentView.addSubview(contentTypeBadgeView)
        self.contentView.addSubview(highlightedView)
        self.contentView.addSubview(selectedView)
        self.contentView.addSubview(selectedBadgeView)

        imageView.autoPinEdgesToSuperviewEdges()
        highlightedView.autoPinEdgesToSuperviewEdges()
        selectedView.autoPinEdgesToSuperviewEdges()

        // Note assets were rendered to match exactly. We don't want to re-size with
        // content mode lest they become less legible.
        let kContentTypeBadgeSize = CGSize(width: 18, height: 12)
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .leading, withInset: 3)
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)
        contentTypeBadgeView.autoSetDimensions(to: kContentTypeBadgeSize)

        let kSelectedBadgeSize = CGSize(width: 31, height: 31)
        selectedBadgeView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 0)
        selectedBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 0)
        selectedBadgeView.autoSetDimensions(to: kSelectedBadgeSize)
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    public func configure(item: MediaGalleryItem) {
        self.item = item
        if let image = item.thumbnailImage(async: {
            [weak self] (image) in
            guard let strongSelf = self else {
                return
            }
            guard strongSelf.item == item else {
                return
            }
            strongSelf.imageView.image = image
            strongSelf.imageView.backgroundColor = UIColor.clear
        }) {
            self.imageView.image = image
            self.imageView.backgroundColor = UIColor.clear
        } else {
            // TODO: Show a placeholder?
            self.imageView.backgroundColor = Theme.offBackgroundColor
        }

        if item.isVideo {
            self.contentTypeBadgeView.isHidden = false
            self.contentTypeBadgeView.image = MediaGalleryCell.videoBadgeImage
        } else if item.isAnimated {
            self.contentTypeBadgeView.isHidden = false
            self.contentTypeBadgeView.image = MediaGalleryCell.animatedBadgeImage
        } else {
            assert(item.isImage)
            self.contentTypeBadgeView.isHidden = true
        }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        self.item = nil
        self.imageView.image = nil
        self.contentTypeBadgeView.isHidden = true
        self.highlightedView.isHidden = true
        self.selectedView.isHidden = true
        self.selectedBadgeView.isHidden = true
    }
}
