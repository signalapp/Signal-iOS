//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalServiceKit
import SignalUI

extension MediaTileViewController: MediaGalleryCollectionViewUpdaterDelegate {

    private func indexSet(_ mediaGallerySectionIndexSet: MediaGallerySectionIndexSet) -> IndexSet {
        return mediaGallerySectionIndexSet.indexSet.shifted(by: 1)
    }

    func updaterDeleteSections(_ sections: MediaGallerySectionIndexSet) {
        collectionView?.deleteSections(indexSet(sections))
    }

    func updaterDeleteItems(at indexPaths: [MediaGalleryIndexPath]) {
        collectionView?.deleteItems(at: indexPaths.map {
            self.indexPath($0)
        })
    }

    func updaterInsertSections(_ sections: MediaGallerySectionIndexSet) {
        collectionView?.insertSections(indexSet(sections))
    }

    func updaterReloadItems(at indexPaths: [MediaGalleryIndexPath]) {
        collectionView?.reloadItems(at: indexPaths.map {
            self.indexPath($0)
        })
    }

    func updaterReloadSections(_ sections: MediaGallerySectionIndexSet) {
        collectionView?.reloadSections(indexSet(sections))
    }

    func updaterDidFinish(numberOfSectionsBefore: Int, numberOfSectionsAfter: Int) {
        Logger.debug("\(numberOfSectionsBefore) -> \(numberOfSectionsAfter)")
        owsAssert(numberOfSectionsAfter == mediaGallery.galleryDates.count)
        if numberOfSectionsBefore == 0 && numberOfSectionsAfter > 0 {
            // Adding a "load newer" section. It goes at the end.
            collectionView?.insertSections(IndexSet(integer: localSection(numberOfSectionsAfter)))
        } else if numberOfSectionsBefore > 0 && numberOfSectionsAfter == 0 {
            // Remove "load earlier" section at the beginning.
            collectionView?.deleteSections(IndexSet(integer: 0))
        }
        accessoriesHelper.updateFooterBarState()
    }
}

class MediaTileViewController: UICollectionViewController, MediaGalleryDelegate, UICollectionViewDelegateFlowLayout {

    private typealias Cell = (UICollectionViewCell & MediaGalleryCollectionViewCell)
    private typealias CollectionViewLayout = UICollectionViewFlowLayout & ScrollPositionPreserving
    private enum Layout {
        case list
        case grid

        func reuseIdentifier(fileType: AllMediaFileType) -> String {
            switch fileType {
            case .photoVideo:
                switch self {
                case .list:
                    return WidePhotoCell.reuseIdentifier
                case .grid:
                    return MediaTileCollectionViewCell.reuseIdentifier
                }
            case .audio:
                return AudioCell.reuseIdentifier
            }
        }
    }

    private let thread: TSThread
    private let accessoriesHelper: MediaGalleryAccessoriesHelper
    private let spoilerState: SpoilerRenderState

    private lazy var mediaGallery: MediaGallery = {
        let mediaGallery = MediaGallery(thread: thread, fileType: fileType, spoilerState: spoilerState)
        mediaGallery.addDelegate(self)
        return mediaGallery
    }()
    private var currentCollectionViewLayout: CollectionViewLayout
    private var allCells = WeakArray<UICollectionViewCell>()

    internal var fileType: AllMediaFileType = AllMediaFileType.defaultValue
    private var layout = Layout.grid

    func set(fileType: AllMediaFileType, isGridLayout: Bool) {
        UIView.performWithoutAnimation {
            let fileTypeChanged = self.fileType != fileType
            if fileTypeChanged {
                mediaGallery.removeAllDelegates()
                mediaGallery = MediaGallery(thread: thread, fileType: fileType, spoilerState: spoilerState)
                mediaGallery.addDelegate(self)
                self.fileType = fileType
            }
            let layout: Layout = isGridLayout ? .grid : .list
            let layoutChanged = self.layout != layout
            var indexPath: IndexPath?
            if layoutChanged || fileTypeChanged {
                self.layout = layout
                indexPath = oldestVisibleIndexPath
                rebuildLayout()
            }
            if fileTypeChanged {
                collectionView.reloadData()
                _ = mediaGallery.loadEarlierSections(batchSize: kLoadBatchSize)
                if !mediaGallery.galleryDates.isEmpty {
                    eagerlyLoadMoreIfPossible()
                }
                collectionView.reloadData()
                if mediaGallery.galleryDates.count > 0 {
                    let lastSectionItemCount = mediaGallery.numberOfItemsInSection(mediaGallery.galleryDates.count - 1)
                    indexPath = IndexPath(item: lastSectionItemCount - 1, section: mediaGallery.galleryDates.count)
                } else {
                    indexPath = nil
                }
            }

            collectionView.layoutIfNeeded()
            if let indexPath {
                if fileTypeChanged {
                    collectionView.scrollToItem(at: indexPath, at: .bottom, animated: false)
                } else {
                    collectionView.scrollToItem(at: indexPath, at: .top, animated: false)
                }
            }
        }
    }

    /// This is used to avoid running two animations concurrently. It doesn't look good on iOS 16 (and probably all other versions).
    private var activeAnimationCount = 0

    public init(
        thread: TSThread,
        accessoriesHelper: MediaGalleryAccessoriesHelper,
        spoilerState: SpoilerRenderState
    ) {
        self.thread = thread
        self.accessoriesHelper = accessoriesHelper
        self.spoilerState = spoilerState
        let layout = Self.buildLayout(layout, fileType: fileType)
        self.currentCollectionViewLayout = layout
        super.init(collectionViewLayout: layout)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Subviews

    // CV section index to MG section index
    private func mediaGallerySection(_ section: Int) -> Int {
        return section - 1
    }

    // MG section index to CV section index
    private func localSection(_ section: Int) -> Int {
        return section + 1
    }

    // CV index path to MG
    private func mediaGalleryIndexPath(_ indexPath: IndexPath) -> MediaGalleryIndexPath {
        var temp = indexPath
        temp.section = mediaGallerySection(indexPath.section)

        return MediaGalleryIndexPath(temp)
    }

    private func indexPath(_ mediaGalleryIndexPath: MediaGalleryIndexPath) -> IndexPath {
        var temp = mediaGalleryIndexPath.indexPath
        temp.section = localSection(mediaGalleryIndexPath.section)
        return temp
    }

    private var indexPathsOfVisibleRealItems: [IndexPath] {
        let numberOfDates = mediaGallery.galleryDates.count
        return reallyVisibleIndexPaths.filter { path in
            path.section > 0 && path.section <= numberOfDates
        }.sorted { lhs, rhs in
            lhs < rhs
        }
    }

    private var oldestVisibleIndexPath: IndexPath? {
        return indexPathsOfVisibleRealItems.min { lhs, rhs in
            lhs.section < rhs.section
        }
    }

    private func filter(_ mediaType: MediaGallery.MediaType) {
        let maybeDate = oldestVisibleIndexPath.map { mediaGallery.galleryDates[mediaGallerySection($0.section)] }
        let indexPathToScrollTo = mediaGallery.setAllowedMediaType(
            mediaType,
            loadUntil: maybeDate ?? GalleryDate(date: Date.distantPast),
            batchSize: kLoadBatchSize,
            firstVisibleIndexPath: oldestVisibleIndexPath.map { mediaGalleryIndexPath($0) }
        )

        if let indexPath = indexPathToScrollTo {
            // Scroll to approximately where you were before.
            collectionView.scrollToItem(at: self.indexPath(indexPath),
                                        at: .top,
                                        animated: false)
        }
        eagerLoadingDidComplete = false
        eagerlyLoadMoreIfPossible()

        accessoriesHelper.updateFooterBarState()
    }

    // MARK: View Lifecycle Overrides

    override func loadView() {
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: collectionViewLayout)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = MediaStrings.allMedia

        collectionView.register(MediaTileCollectionViewCell.self, forCellWithReuseIdentifier: MediaTileCollectionViewCell.reuseIdentifier)
        collectionView.register(WidePhotoCell.self, forCellWithReuseIdentifier: WidePhotoCell.reuseIdentifier)
        collectionView.register(AudioCell.self, forCellWithReuseIdentifier: AudioCell.reuseIdentifier)
        collectionView.register(
            MediaGalleryDateHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: MediaGalleryDateHeader.reuseIdentifier
        )
        collectionView.register(
            MediaGalleryStaticHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier
        )
        collectionView.register(
            MediaGalleryEmptyContentView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: MediaGalleryEmptyContentView.reuseIdentifier
        )
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.preservesSuperviewLayoutMargins = true
        collectionView.backgroundColor = UIColor(dynamicProvider: { _ in Theme.tableView2PresentedBackgroundColor })

        accessoriesHelper.installViews()

        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeCategoryDidChange), name: UIContentSizeCategory.didChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .themeDidChange, object: nil)
        applyTheme()
    }

    override func viewWillAppear(_ animated: Bool) {
        defer { super.viewWillAppear(animated) }

        // You must layout before mutating mediaGallery. Otherwise, MediaTileViewLayout.prepare() could be
        // called while processing an update. That will violate the exclusive access rules since it calls
        // (indirectly) into MediaGallerySections.
        view.layoutIfNeeded()

        if mediaGallery.galleryDates.isEmpty {
            _ = self.mediaGallery.loadEarlierSections(batchSize: kLoadBatchSize)
            if mediaGallery.galleryDates.isEmpty {
                // There must be no media.
                return
            }
            eagerlyLoadMoreIfPossible()
        }
        let cvAudioPlayer = AppEnvironment.shared.cvAudioPlayerRef
        cvAudioPlayer.shouldAutoplayNextAudioAttachment = { [weak self] in
            if self?.view.window == nil {
                return true
            }
            if self?.presentedViewController != nil {
                return true
            }
            if self?.navigationController?.topViewController != self?.parent {
                return true
            }
            return false
        }
        let lastSectionItemCount = mediaGallery.numberOfItemsInSection(mediaGallery.galleryDates.count - 1)
        collectionView.scrollToItem(
            at: IndexPath(item: lastSectionItemCount - 1, section: mediaGallery.galleryDates.count),
            at: .bottom,
            animated: false
        )
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        cvAudioPlayer.shouldAutoplayNextAudioAttachment = nil
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in
            self.recalculateLayoutMetrics()
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        recalculateLayoutMetrics()
    }

    // MARK: Theme

    @objc
    private func applyTheme() {
        accessoriesHelper.applyTheme()
    }

    @objc
    private func contentSizeCategoryDidChange() {
        cachedDateHeaderHeight = nil
        cachedLoadingDataHeaderHeight = nil
        if layout == .list {
            recalculateListLayoutMetrics()
        }
        currentCollectionViewLayout.invalidateLayout()
    }

    // MARK: Orientation

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.defaultSupportedOrientations
    }

    // MARK: - List View / Grid View

    private func rebuildLayout() {
        currentCollectionViewLayout = Self.buildLayout(layout, fileType: fileType)
        collectionView.setCollectionViewLayout(currentCollectionViewLayout, animated: false)
        collectionView.reloadData()
    }

    // MARK: UICollectionViewDelegate

    private let scrollFlag = MediaTileScrollFlag()

    private var willDecelerate = false {
        didSet {
            if oldValue && !willDecelerate {
                mediaGallery.runAsyncCompletionsIfPossible()
            }
        }
    }

    private var scrollingToTop = false

    override func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        scrollingToTop = true
        return true
    }

    override func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        scrollingToTop = false
        showOrHideScrollFlag()
    }

    override func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        willDecelerate = decelerate
    }

    override func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        willDecelerate = false
        showOrHideScrollFlag()
    }

    private var scrollFlagShouldBeVisible = false

    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.autoLoadMoreIfNecessary()
        showOrHideScrollFlag()
        if scrollFlag.superview != nil {
            updateScrollFlag()
        }
    }

    private func showOrHideScrollFlag() {
        if collectionView.isTracking || scrollingToTop {
            willDecelerate = false
            scrollFlagShouldBeVisible = true
            if scrollFlag.superview == nil {
                collectionView?.addSubview(scrollFlag)
            }
            scrollFlag.alpha = 1.0
        } else if scrollFlagShouldBeVisible && !willDecelerate {
            scrollFlagShouldBeVisible = false
            UIView.animate(withDuration: 0.25) {
                self.scrollFlag.alpha = 0.0
            }
        }
    }

    // Like indexPathsForVisibleItems but excludes those obscured by the navigation bar.
    private var reallyVisibleIndexPaths: [IndexPath] {
        guard let superview = collectionView.superview else {
            return []
        }
        let visibleFrame = collectionView.convert(collectionView.frame.inset(by: collectionView.safeAreaInsets),
                                                  from: superview)
        return collectionView.indexPathsForVisibleItems.filter { indexPath in
            guard let cell = collectionView.cellForItem(at: indexPath) else {
                return false
            }
            return cell.frame.intersects(visibleFrame)
        }
    }

    private func updateScrollFlag() {
        guard mediaGallery.galleryDates.count > 0,
              let indexPath = reallyVisibleIndexPaths.min() else {
            scrollFlag.alpha = 0.0
            return
        }
        let i = mediaGallerySection(indexPath.section)
        let date = mediaGallery.galleryDates[i]
        scrollFlag.stringValue = date.localizedString
        scrollFlag.sizeToFit()

        let center = guessCenterOfFlag()
        if center.x.isFinite && center.y.isFinite {
            scrollFlag.center = guessCenterOfFlag()
        }
    }

    private func guessCenterOfFlag() -> CGPoint {
        let currentOffset = collectionView.contentOffset.y
        let contentHeight = collectionView.contentSize.height
        let visibleHeight = collectionView.bounds.height

        // This crazy mess is to figure out where the scroll indicator is. It is complicated by
        // the fact that the scrollbar's exact location is not exposed, nor is the minimum
        // height of the indicator.

        let scrollbarInsets = {
            // This code is cursed and I'm sorry.
            switch UIApplication.shared.statusBarOrientation {
            case .portrait, .portraitUpsideDown, .unknown, .landscapeRight:
                // Note that adjustedContentInset is used because it seems to include the
                // rounded corners of the device, whereas safeAreaInsets is not enough.
                var result = collectionView.adjustedContentInset
                if UIDevice.current.userInterfaceIdiom == .pad {
                    result.bottom = 8.0
                }
                result.right = 0
                if collectionView.verticalScrollIndicatorInsets.bottom > 0 {
                    // Footer height takes precedence over adjustedContentInset, which is not terribly accurate.
                    result.bottom = collectionView.verticalScrollIndicatorInsets.bottom
                }
                return result
            case .landscapeLeft:
                // In landscape the horizontal line to indicate swipe direction makes the bottom inset
                // too big. safeAreaInsets isn't right either. I don't think iOS exposes anything so
                // I'm hardcoding this until a better idea comes along.
                var result = collectionView.adjustedContentInset
                result.bottom = 8.0
                // In landscape left the scroll indicator is shifted way in, but its adjusted
                // content inset is 0.
                result.right = collectionView.safeAreaInsets.right
                if collectionView.verticalScrollIndicatorInsets.bottom > 0 {
                    // Footer height takes precedence over adjustedContentInset, which is not terribly accurate.
                    result.bottom = collectionView.verticalScrollIndicatorInsets.bottom
                }
                return result
            @unknown default:
                return collectionView.adjustedContentInset
            }
        }()
        // If iOS had a scrollbar, `scrollbarHeight` is how tall it would be. The scroll
        // indicator moves through an area of this height.
        let scrollbarHeight = collectionView.frame.height - scrollbarInsets.top - scrollbarInsets.bottom
        let rightInset = 20.0 + scrollbarInsets.right

        // Set a minimum height for the handle. iOS has no API for this.
        let minimumHandleHeight = UIDevice.current.userInterfaceIdiom == .pad ? 42.0 : 36.0

        // How much of the content is visible?
        let fractionVisible = visibleHeight / contentHeight

        // Guess how tall the indicator is.
        let indicatorHeight = max(minimumHandleHeight,
                                  scrollbarHeight * fractionVisible)

        // First we calculate what fraction (from 0 to 1) is the top of the visible area at. This can't move through
        // the entire contentSize (except during overscroll, which we ignore). Reucing the denominator by visibleHeight
        // ensures it's at 1.0 when you're scrolled all the way down.
        let topFrac = collectionView.contentOffset.y / max(collectionView.contentOffset.y,
                                                           collectionView.contentSize.height - visibleHeight)
        // Next we figure out what the "range of motion" of the indicator is. It can only move through
        // scrollbarHeight minus its minimum height.
        let indicatorRangeOfMotion = scrollbarHeight - indicatorHeight

        // Now it's easy to calculate the vertical offset of the *top* of the indicator within the scrollbar.
        let indicatorOffsetInScrollbar = indicatorRangeOfMotion * topFrac

        // Calculate the top of the scrollbar.
        let scrollbarMinY = scrollbarInsets.top + currentOffset

        // Finally, we can calculate the coordinate of the vertical center of the indicator.
        let indicatorMidY = indicatorOffsetInScrollbar + indicatorHeight / 2.0 + scrollbarMinY

        let center = CGPoint(
            x: collectionView.bounds.width - rightInset - scrollFlag.bounds.width / 2.0,
            y: indicatorMidY
        )
        return center
    }

    private var previousAdjustedContentInset: UIEdgeInsets = UIEdgeInsets()

    override func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
        defer { previousAdjustedContentInset = scrollView.adjustedContentInset }
        guard !mediaGallery.galleryDates.isEmpty else {
            return
        }

        if scrollView.contentSize.height > scrollView.bounds.height - scrollView.adjustedContentInset.totalHeight {
            // Were we pinned to the bottom before? If so, scroll back down.
            let dy = scrollView.adjustedContentInset.totalHeight - previousAdjustedContentInset.totalHeight
            if scrollView.contentOffset.y + dy + scrollView.bounds.height >= scrollView.contentSize.height {
                scrollView.contentOffset.y =
                    scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
            }
        }

        updateScrollFlag()
    }

    override func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {

        Logger.debug("")

        guard !mediaGallery.galleryDates.isEmpty else {
            return false
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx, loadNewerSectionIdx:
            return false
        default:
            return true
        }
    }

    override func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {

        Logger.debug("")

        guard !mediaGallery.galleryDates.isEmpty else {
            return false
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx, loadNewerSectionIdx:
            return false
        default:
            return true
        }
    }

    override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {

        Logger.debug("")

        guard !mediaGallery.galleryDates.isEmpty else {
            return false
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx, loadNewerSectionIdx:
            return false
        default:
            return true
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.info("")

        guard let gridCell = self.collectionView(collectionView, cellForItemAt: indexPath) as? Cell else {
            owsFailDebug("galleryCell was unexpectedly nil")
            return
        }

        guard let attachmentStream = gridCell.item?.attachmentStream else {
            owsFailDebug("galleryItem was unexpectedly nil")
            return
        }

        if accessoriesHelper.isInBatchSelectMode {
            accessoriesHelper.didModifySelection()
        } else {
            collectionView.deselectItem(at: indexPath, animated: true)

            guard let pageVC = MediaPageViewController(
                initialMediaAttachment: attachmentStream,
                mediaGallery: mediaGallery,
                spoilerState: spoilerState
            ) else {
                return
            }

            present(pageVC, animated: true)
        }
    }

    override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        Logger.debug("")

        accessoriesHelper.didModifySelection()
    }

    // MARK: UICollectionViewDataSource

    override func numberOfSections(in collectionView: UICollectionView) -> Int {
        Logger.debug("")

        let dates = mediaGallery.galleryDates
        guard !dates.isEmpty else {
            // empty gallery
            Logger.debug("No gallery dates - return 1")
            return 1
        }

        // One for each galleryDate plus a "loading older" and "loading newer" section
        let count = dates.count
        Logger.debug("\(count) gallery dates - return \(count + 2)")
        return count + 2
    }

    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        guard !mediaGallery.galleryDates.isEmpty else {
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

        let count = mediaGallery.numberOfItemsInSection(mediaGallerySection(sectionIdx))
        return count
    }

    override func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {

        let defaultView: (() -> UICollectionReusableView) = { UICollectionReusableView() }

        guard !mediaGallery.galleryDates.isEmpty else {
            guard
                let sectionHeader = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: MediaGalleryEmptyContentView.reuseIdentifier,
                    for: indexPath
                ) as? MediaGalleryEmptyContentView else {
                owsFailDebug("unable to build section header for kLoadOlderSectionIdx")
                return defaultView()
            }
            sectionHeader.contentType = fileType
            sectionHeader.isFilterOn = isFiltering
            sectionHeader.clearFilterAction = { [weak self] in
                self?.disableFiltering()
            }
            return sectionHeader
        }

        if kind == UICollectionView.elementKindSectionHeader {
            switch indexPath.section {
            case kLoadOlderSectionIdx:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier,
                    for: indexPath
                ) as? MediaGalleryStaticHeader else {
                    owsFailDebug("unable to build section header for \(indexPath)")
                    return defaultView()
                }
                sectionHeader.titleLabel.text = OWSLocalizedString(
                    "GALLERY_TILES_LOADING_OLDER_LABEL",
                    comment: "Label indicating loading is in progress"
                )
                return sectionHeader
            case loadNewerSectionIdx:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier,
                    for: indexPath
                ) as? MediaGalleryStaticHeader else {
                    owsFailDebug("unable to build section header for \(indexPath)")
                    return defaultView()
                }
                sectionHeader.titleLabel.text = OWSLocalizedString(
                    "GALLERY_TILES_LOADING_MORE_RECENT_LABEL",
                    comment: "Label indicating loading is in progress"
                )
                return sectionHeader
            default:
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(
                    ofKind: kind,
                    withReuseIdentifier: MediaGalleryDateHeader.reuseIdentifier,
                    for: indexPath
                ) as? MediaGalleryDateHeader else {
                    owsFailDebug("unable to build section header for indexPath: \(indexPath)")
                    return defaultView()
                }
                guard let date = mediaGallery.galleryDates[safe: mediaGallerySection(indexPath.section)] else {
                    owsFailDebug("unknown section for indexPath: \(indexPath)")
                    return defaultView()
                }
                sectionHeader.leadingEdgeTextInset = layout == .grid ? 0 : 8
                if let wideMediaTileViewLayout = currentCollectionViewLayout as? WideMediaTileViewLayout {
                    sectionHeader.textMarginBottomAdjustment = wideMediaTileViewLayout.contentCardVerticalInset
                } else {
                    sectionHeader.textMarginBottomAdjustment = 0
                }
                sectionHeader.configure(title: date.localizedString)
                return sectionHeader
            }
        }

        return defaultView()
    }

    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        Logger.debug("indexPath: \(indexPath)")

        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: layout.reuseIdentifier(fileType: fileType), for: indexPath) as? Cell else {
            owsFailDebug("unexpected cell for indexPath: \(indexPath)")
            return UICollectionViewCell()
        }
        allCells.cullExpired()
        if !allCells.contains(cell) {
            allCells.append(cell)
        }
        cell.indexPathDidChange(indexPath, itemCount: collectionView.numberOfItems(inSection: indexPath.section))
        guard !mediaGallery.galleryDates.isEmpty else {
            owsFailDebug("unexpected cell for loadNewerSectionIdx")
            cell.makePlaceholder()
            return cell
        }

        switch indexPath.section {
        case kLoadOlderSectionIdx:
            owsFailDebug("unexpected cell for kLoadOlderSectionIdx")
            cell.makePlaceholder()
        case loadNewerSectionIdx:
            owsFailDebug("unexpected cell for loadNewerSectionIdx")
            cell.makePlaceholder()
        default:
            // Loading must be done asynchronously because this can be called while applying a
            // pending update. Attempting to mutate MediaGallerySections synchronously could cause a
            // deadlock.
            guard let galleryItem = galleryItem(at: indexPath, loadAsync: true) else {
                Logger.debug("Using placeholder for unloaded path \(indexPath)")
                cell.makePlaceholder()
                break
            }

            VideoDurationHelper.shared.with(context: videoDurationContext) {
                cell.configure(item: cellItem(for: galleryItem), spoilerState: spoilerState)
            }
        }
        return cell
    }

    private let mediaCache = CVMediaCache()

    private func cellItem(for galleryItem: MediaGalleryItem) -> MediaGalleryCellItem {
        switch fileType {
        case .photoVideo:
            return .photoVideo(MediaGalleryCellItemPhotoVideo(galleryItem: galleryItem))
        case .audio:
            return .audio(MediaGalleryCellItemAudio(
                message: galleryItem.message,
                interaction: galleryItem.message,
                thread: thread,
                attachmentStream: galleryItem.attachmentStream,
                mediaCache: mediaCache,
                metadata: galleryItem.mediaMetadata!
            ))
        }
    }
    private lazy var videoDurationContext = { VideoDurationHelper.Context() }()

    override func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let cell = cell as? Cell else {
            owsFailDebug("unexpected cell: \(cell)")
            return
        }

        cell.setAllowsMultipleSelection(collectionView.allowsMultipleSelection, animated: false)
    }

    private func galleryItem(at indexPath: IndexPath, loadAsync: Bool = false) -> MediaGalleryItem? {
        let underlyingPath = mediaGalleryIndexPath(indexPath)
        if let loadedGalleryItem = mediaGallery.galleryItem(at: underlyingPath) {
            return loadedGalleryItem
        }

        mediaGallery.ensureGalleryItemsLoaded(.after,
                                              sectionIndex: underlyingPath.section,
                                              itemIndex: underlyingPath.item,
                                              amount: kLoadBatchSize,
                                              shouldLoadAlbumRemainder: false,
                                              async: loadAsync,
                                              userData: MediaGalleryUpdateUserData(disableAnimations: true))

        return mediaGallery.galleryItem(at: underlyingPath)
    }

    private func updateVisibleCells() {
        for cell in collectionView.visibleCells {
            guard let cell = cell as? Cell else {
                owsFailDebug("unexpected cell: \(cell)")
                continue
            }

            cell.setAllowsMultipleSelection(collectionView.allowsMultipleSelection, animated: true)
        }
    }

    // MARK: UICollectionViewDelegateFlowLayout

    private static let invalidLayoutItemSize = CGSize(square: 10)

    private class func buildLayout(_ layout: Layout, fileType: AllMediaFileType) -> CollectionViewLayout {
        let layout: CollectionViewLayout = {
            switch layout {
            case .list:
                switch fileType {
                case .photoVideo:
                    return WideMediaTileViewLayout(contentCardVerticalInset: WidePhotoCell.contentCardVerticalInset)
                case .audio:
                    return WideMediaTileViewLayout(contentCardVerticalInset: AudioCell.contentCardVerticalInset)
                }
            case .grid:
                return SquareMediaTileViewLayout()
            }
        }()

        layout.itemSize = invalidLayoutItemSize
        layout.sectionInsetReference = .fromSafeArea
        layout.sectionHeadersPinToVisibleBounds = false

        return layout
    }

    private func recalculateLayoutMetrics() {
        switch layout {
        case .grid:
            recalculateGridLayoutMetrics()
        case .list:
            recalculateListLayoutMetrics()
        }
    }

    private func recalculateGridLayoutMetrics() {
        let kItemsPerPortraitRow = 4

        let containerSize = view.safeAreaLayoutGuide.layoutFrame.size
        let minimumViewWidth = min(containerSize.width, containerSize.height)
        let approxItemWidth = minimumViewWidth / CGFloat(kItemsPerPortraitRow)

        let itemCount = round(containerSize.width / approxItemWidth)
        let interSpaceWidth = (itemCount - 1) * currentCollectionViewLayout.minimumInteritemSpacing
        let availableWidth = max(0, containerSize.width - interSpaceWidth)

        let itemWidth = floor(availableWidth / CGFloat(itemCount))
        let newItemSize = CGSize(square: itemWidth)
        if newItemSize != currentCollectionViewLayout.itemSize {
            currentCollectionViewLayout.itemSize = newItemSize
            currentCollectionViewLayout.invalidateLayout()
        }
    }

    private func recalculateListLayoutMetrics() {
        let horizontalSectionInset: CGFloat
        let cellHeight: CGFloat

        switch fileType {
        case .photoVideo:
            horizontalSectionInset = OWSTableViewController2.defaultHOuterMargin
            cellHeight = WidePhotoCell.cellHeight()
        case .audio:
            horizontalSectionInset = 0
            cellHeight = AudioCell.defaultCellHeight
        }

        let newItemSize = CGSize(
            width: floor(view.safeAreaLayoutGuide.layoutFrame.size.width) - horizontalSectionInset * 2,
            height: cellHeight
        )
        if newItemSize != currentCollectionViewLayout.itemSize || horizontalSectionInset != currentCollectionViewLayout.sectionInset.left {
            currentCollectionViewLayout.itemSize = newItemSize
            currentCollectionViewLayout.sectionInset = UIEdgeInsets(hMargin: horizontalSectionInset, vMargin: 0)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {

        guard !mediaGallery.galleryDates.isEmpty else {
            // Make section header occupy entire visible collection view heigth so that the text is centered.
            let collectionViewViewportHeight = collectionView.frame.height - collectionView.adjustedContentInset.totalHeight
            return CGSize(width: collectionView.frame.height, height: collectionViewViewportHeight)
        }

        let height: CGFloat = {
            switch section {
            case kLoadOlderSectionIdx:
                // Show "loading older..." iff there is still older data to be fetched
                return mediaGallery.hasFetchedOldest ? 0 : loadingDataHeaderHeight()
            case loadNewerSectionIdx:
                // Show "loading newer..." iff there is still more recent data to be fetched
                return mediaGallery.hasFetchedMostRecent ? 0 : loadingDataHeaderHeight()
            default:
                return dateHeaderHeight()
            }
        }()
        guard height > 0 else {
            // No section header
            return .zero
        }
        return CGSize(width: collectionView.frame.width, height: height)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        insetForSectionAt section: Int
    ) -> UIEdgeInsets {
        guard !mediaGallery.galleryDates.isEmpty else { return .zero }

        guard layout == .list else { return .zero }

        if section == loadNewerSectionIdx {
            // Additional 16pt margin at the bottom of the list.
            return UIEdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0)
        }

        return currentCollectionViewLayout.sectionInset
    }

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard currentCollectionViewLayout == collectionViewLayout else {
            owsFailDebug("Unknown layout")
            return .zero
        }

        if currentCollectionViewLayout.itemSize == Self.invalidLayoutItemSize {
            recalculateLayoutMetrics()
        }

        switch layout {
        case .grid:
            return currentCollectionViewLayout.itemSize
        case .list:
            switch fileType {
            case .photoVideo:
                return currentCollectionViewLayout.itemSize
            case .audio:
                let defaultCellSize = currentCollectionViewLayout.itemSize
                if let galleryItem = galleryItem(at: indexPath, loadAsync: true) {
                    let cellItem = cellItem(for: galleryItem)
                    let cellHeight = AudioCell.cellHeight(for: cellItem, maxWidth: defaultCellSize.width)
                    return CGSize(width: defaultCellSize.width, height: cellHeight)
                }
                return defaultCellSize
            }
        }
    }

    private var cachedDateHeaderHeight: CGFloat?
    private var cachedLoadingDataHeaderHeight: CGFloat?

    private func dateHeaderHeight() -> CGFloat {
        var headerHeight: CGFloat
        if let cachedDateHeaderHeight {
            headerHeight = cachedDateHeaderHeight
        } else {
            let headerView = MediaGalleryDateHeader()
            headerView.configure(title: "M")
            headerHeight = headerView.systemLayoutSizeFitting(UIView.layoutFittingExpandedSize).height
            cachedDateHeaderHeight = headerHeight
        }
        if let wideMediaTileLayout = currentCollectionViewLayout as? WideMediaTileViewLayout {
            headerHeight -= wideMediaTileLayout.contentCardVerticalInset
        }
        return headerHeight
    }

    private func loadingDataHeaderHeight() -> CGFloat {
        if let cachedLoadingDataHeaderHeight {
            return cachedLoadingDataHeaderHeight
        }
        let headerView = MediaGalleryStaticHeader()
        headerView.titleLabel.text = "M"
        let size = headerView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        cachedLoadingDataHeaderHeight = size.height
        return size.height
    }

    // MARK: MediaGalleryDelegate

    private func updateCellIndexPaths() {
        for cell in allCells.elements {
            guard let indexPath = collectionView.indexPath(for: cell) else {
                continue
            }
            (cell as? Cell)?.indexPathDidChange(indexPath,
                                                itemCount: collectionView.numberOfItems(inSection: indexPath.section))
        }
    }

    func mediaGallery(_ mediaGallery: MediaGallery, applyUpdate update: MediaGallery.Update) {
        Logger.debug("Will begin batch update. animating=\(activeAnimationCount)")
        let shouldAnimate = activeAnimationCount == 0 && !update.userData.contains(where: { $0.disableAnimations })

        let saved = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(shouldAnimate && UIView.areAnimationsEnabled && saved)

        if update.userData.contains(where: { $0.shouldRecordContentSizeBeforeInsertingToTop }) {
            currentCollectionViewLayout.recordContentSizeBeforeInsertingToTop()
        }
        // Within `performBatchUpdates` and before our closure runs, `UICollectionView` may call `numberOfItemsInSection`
        // and it will expect us to give it "old" values (before any changes are applied).
        self.collectionView.performBatchUpdates {
            Logger.debug("Did begin batch update")

            let oldItemCounts = (0..<self.mediaGallery.galleryDates.count).map {
                self.mediaGallery.numberOfItemsInSection($0)
            }

            // This causes "new" values to become visible.
            let journal = update.commit()

            var updater = MediaGalleryCollectionViewUpdater(
                itemCounts: oldItemCounts)
            updater.delegate = self
            updater.update(journal)

            Logger.debug("Finished batch update")
        } completion: { [weak self] _ in
            if shouldAnimate {
                self?.activeAnimationCount -= 1
            }
        }
        updateCellIndexPaths()

        UIView.setAnimationsEnabled(saved)
        if shouldAnimate {
            activeAnimationCount += 1
        }
    }

    func mediaGallery(_ mediaGallery: MediaGallery, willDelete items: [MediaGalleryItem], initiatedBy: AnyObject) {
        Logger.debug("")
    }

    func mediaGalleryDidDeleteItem(_ mediaGallery: MediaGallery) {
        Logger.debug("")
    }

    func mediaGalleryDidReloadItems(_ mediaGallery: MediaGallery) {
    }

    func didAddSectionInMediaGallery(_ mediaGallery: MediaGallery) {
        _ = mediaGallery.loadLaterSections(batchSize: kLoadBatchSize)
    }

    func didReloadAllSectionsInMediaGallery(_ mediaGallery: MediaGallery) {
        // If you receive a new attachment for an earlier month, MediaGallerySections resets itself and throws out a bunch of data.
        // It resets hasFetched{Oldest,MostRecent} to false. This causes "Loading older…" and "Loading newer…" to become visible,
        // even if there are no older or newer months in the db. Those only get updated on scroll.
        // If the collection view's content size is less than its visible size then scrolling is impossible and they are stuck forever.
        // Load sections until we either have everything or there's enough room for the user to scroll.
        while collectionView.contentSize.height < collectionView.visibleSize.height && (!mediaGallery.hasFetchedOldest || !mediaGallery.hasFetchedMostRecent) {
            if !mediaGallery.hasFetchedOldest {
                _ = mediaGallery.loadEarlierSections(batchSize: kLoadBatchSize)
            }
            if !mediaGallery.hasFetchedMostRecent {
                _ = mediaGallery.loadLaterSections(batchSize: kLoadBatchSize)
            }
        }
        if eagerLoadingDidComplete {
            // There might be more to load so restart eager loading.
            eagerLoadingDidComplete = false
            eagerlyLoadMoreIfPossible()
        }
    }

    func mediaGalleryShouldDeferUpdate(_ mediaGallery: MediaGallery) -> Bool {
        return willDecelerate
    }

    // MARK: Lazy Loading

    var isFetchingMoreData = false
    let kLoadBatchSize: Int = 100

    let kLoadOlderSectionIdx: Int = 0
    var loadNewerSectionIdx: Int {
        return localSection(mediaGallery.galleryDates.count)
    }
    private var eagerLoadingDidComplete = false
    private var eagerLoadOutstanding = false

    private func eagerlyLoadMoreIfPossible() {
        Logger.debug("")
        guard !mediaGallery.hasFetchedOldest else {
            Logger.debug("done")
            eagerLoadingDidComplete = true
            return
        }
        guard !eagerLoadOutstanding else {
            Logger.debug("Already doing an eager load")
            return
        }
        let userData = MediaGalleryUpdateUserData(disableAnimations: true,
                                                  shouldRecordContentSizeBeforeInsertingToTop: true)
        eagerLoadOutstanding = true
        // This is a low priority update because we never want eager loads to starve user-initiated
        // loads (such as loading more sections because of scrolling or loading items to display).
        Logger.debug("Will eagerly load earlier sections")
        mediaGallery.asyncLoadEarlierSections(batchSize: kLoadBatchSize,
                                              highPriority: false,
                                              userData: userData) { [weak self] newSections in
            Logger.debug("Eagerly loaded \(newSections)")
            self?.eagerLoadOutstanding = false
            self?.eagerlyLoadMoreIfPossible()
        }
    }

    public func autoLoadMoreIfNecessary() {
        let kEdgeThreshold: CGFloat = 800

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        let contentOffsetY = collectionView.contentOffset.y
        let oldContentHeight = collectionView.contentSize.height
        let direction: GalleryDirection

        var shouldRecordContentSizeBeforeInsertingToTop = false
        if contentOffsetY < kEdgeThreshold && !mediaGallery.hasFetchedOldest {
            // Near the top, load older content
            shouldRecordContentSizeBeforeInsertingToTop = true
            direction = .before

        } else if oldContentHeight - contentOffsetY < kEdgeThreshold && !mediaGallery.hasFetchedMostRecent {
            // Near the bottom, load newer content
            direction = .after

        } else {
            return
        }

        guard !isFetchingMoreData else {
            Logger.debug("already fetching more data")
            return
        }

        let userData = MediaGalleryUpdateUserData(disableAnimations: true,
                                                  shouldRecordContentSizeBeforeInsertingToTop: shouldRecordContentSizeBeforeInsertingToTop)

        isFetchingMoreData = true
        switch direction {
        case .before:
            mediaGallery.asyncLoadEarlierSections(batchSize: kLoadBatchSize,
                                                  highPriority: true,
                                                  userData: userData) { [weak self] newSections in
                Logger.debug("found new sections: \(newSections)")
                self?.isFetchingMoreData = false
            }
        case .after:
            mediaGallery.asyncLoadLaterSections(batchSize: kLoadBatchSize, userData: userData) { [weak self] newSections in
                Logger.debug("found new sections: \(newSections)")
                self?.isFetchingMoreData = false
            }
        case .around:
            preconditionFailure() // unused
        }
    }
}

extension MediaTileViewController: MediaPresentationContextProvider {

    func mediaPresentationContext(item: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        // First time presentation can occur before layout.
        view.layoutIfNeeded()

        guard case let .gallery(galleryItem) = item else {
            owsFailDebug("Unexpected media type")
            return nil
        }

        guard let underlyingPath = mediaGallery.indexPath(for: galleryItem) else {
            owsFailDebug("galleryItemIndexPath was unexpectedly nil")
            return nil
        }
        let indexPath = self.indexPath(underlyingPath)

        guard let visibleIndex = collectionView.indexPathsForVisibleItems.firstIndex(of: indexPath) else {
            Logger.debug("visibleIndex was nil, swiped to offscreen gallery item")
            return nil
        }

        guard let cell = collectionView.visibleCells[safe: visibleIndex] as? Cell else {
            owsFailDebug("cell was unexpectedly nil")
            return nil
        }
        return cell.mediaPresentationContext(collectionView: collectionView, in: coordinateSpace)
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }
}

// MARK: - Private Helper Classes

private class MediaGalleryStaticHeader: UICollectionReusableView {

    static let reuseIdentifier = "MediaGalleryStaticHeader"

    let titleLabel: UILabel = {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.font = .dynamicTypeHeadlineClamped
        label.numberOfLines = 2
        label.textColor = UIColor(dynamicProvider: { _ in return Theme.secondaryTextAndIconColor })
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)

        addSubview(titleLabel)
        titleLabel.autoPinEdgesToSuperviewMargins()
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class MediaGalleryDateHeader: UICollectionReusableView {

    static let reuseIdentifier = "MediaGalleryDateHeader"

    private let label: UILabel = {
        let label = UILabel()
        label.adjustsFontForContentSizeCategory = true
        label.font = .dynamicTypeHeadlineClamped
        label.textAlignment = .natural
        label.textColor = UIColor(dynamicProvider: { _ in return Theme.primaryTextColor })
        return label
    }()

    private lazy var labelLeadingEdgeConstraint = label.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor)

    var leadingEdgeTextInset: CGFloat = 0 {
        didSet {
            labelLeadingEdgeConstraint.constant = leadingEdgeTextInset
        }
    }

    private static let textMarginBottom: CGFloat = 10
    // This property allows us to decrease distance between text and bottom edge of the header view
    // with the purpose of keeping vertical spacing between header view text and top edge
    // of the first content "card" in section same (applicable in the list view only).
    var textMarginBottomAdjustment: CGFloat = 0 {
        didSet {
            labelBottomEdgeConstraint.constant = Self.textMarginBottom - textMarginBottomAdjustment
        }
    }
    private lazy var labelBottomEdgeConstraint = bottomAnchor.constraint(equalTo: label.bottomAnchor, constant: Self.textMarginBottom)

    override init(frame: CGRect) {
        super.init(frame: frame)

        preservesSuperviewLayoutMargins = true

        addSubview(label)
        NSLayoutConstraint.activate([ labelLeadingEdgeConstraint, labelBottomEdgeConstraint ])
        label.autoPinTrailingToSuperviewMargin()
        label.autoPinEdge(toSuperviewEdge: .top, withInset: 32)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String) {
        label.text = title
    }
}

private class MediaGalleryEmptyContentView: UICollectionReusableView {

    static let reuseIdentifier = "MediaGalleryEmptyContentView"

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 2
        label.adjustsFontForContentSizeCategory = true
        label.font = .dynamicTypeSubheadlineClamped.semibold()
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        label.textColor = UIColor(dynamicProvider: { _ in Theme.primaryTextColor })
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.numberOfLines = 5
        label.adjustsFontForContentSizeCategory = true
        label.font = .dynamicTypeSubheadlineClamped
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        label.textColor = UIColor(dynamicProvider: { _ in Theme.primaryTextColor })
        return label
    }()

    private lazy var clearFilterButton: UIButton = {
        let buttonTitle = OWSLocalizedString(
            "MEDIA_GALLERY_CLEAR_FILTER_BUTTON",
            comment: "Button to reset media filter. Displayed when filter results in no media visible."
        )
        let button = OutlineButton(type: .custom)
        button.setTitle(buttonTitle, for: .normal)
        button.titleLabel?.font = .dynamicTypeCaption1.semibold()
        button.setTitleColor(UIColor(dynamicProvider: { _ in Theme.secondaryTextAndIconColor }), for: .normal)
        button.setTitleColor(UIColor(dynamicProvider: { _ in Theme.secondaryTextAndIconColor.withAlphaComponent(0.5) }), for: .highlighted)
        button.addTarget(self, action: #selector(clearFilterPressed), for: .touchUpInside)
        return button
    }()

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
        if isFilterOn {
            stackView.addArrangedSubview(clearFilterButton)
        }
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 4
        stackView.setCustomSpacing(8, after: subtitleLabel)
        return stackView
    }()

    var contentType: AllMediaFileType = .photoVideo {
        didSet {
            reload()
        }
    }

    var isFilterOn: Bool = true {
        didSet {
            reload()
        }
    }

    var clearFilterAction: (() -> Void)?

    @objc
    private func clearFilterPressed(_ sender: Any) {
        clearFilterAction?()
    }

    private func reload() {
        let title: String?
        let subtitle: String?

        if isFilterOn {
            title = nil
            subtitle = NSLocalizedString(
                "MEDIA_GALLERY_NO_FILTER_RESULTS",
                comment: "Displayed in All Media screen when there's no media - first line."
            )
        } else {
            switch contentType {
            case .photoVideo:
                title = NSLocalizedString(
                    "MEDIA_GALLERY_NO_MEDIA_TITLE",
                    comment: "Displayed in All Media screen when there's no media - first line."
                )
                subtitle = NSLocalizedString(
                    "MEDIA_GALLERY_NO_MEDIA_SUBTITLE",
                    comment: "Displayed in All Media screen when there's no media - second line."
                )
            case .audio:
                title = NSLocalizedString(
                    "MEDIA_GALLERY_NO_AUDIO_TITLE",
                    comment: "Displayed in All Media (Audio) screen when there's no audio files - first line."
                )
                subtitle = NSLocalizedString(
                    "MEDIA_GALLERY_NO_AUDIO_SUBTITLE",
                    comment: "Displayed in All Media (Audio) screen when there's no audio files - second line."
                )
            }
        }

        titleLabel.text = title
        subtitleLabel.text = subtitle
        if isFilterOn {
            if stackView.arrangedSubviews.count == 2 {
                stackView.addArrangedSubview(clearFilterButton)
            }
            clearFilterButton.isHidden = false
        } else if stackView.arrangedSubviews.count > 2 {
            clearFilterButton.isHidden = true
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(stackView)
        stackView.autoCenterInSuperview()
        stackView.autoPinWidthToSuperview(withMargin: 32, relation: .lessThanOrEqual)
        stackView.autoPinHeightToSuperview(withMargin: 32, relation: .lessThanOrEqual)
        reload()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private class OutlineButton: UIButton {

        private lazy var backgroundPillView: UIView = {
            let view = PillView()
            view.layer.borderWidth = 1.5
            view.layer.borderColor = Self.normalBorderColor.cgColor
            view.isUserInteractionEnabled = false
            return view
        }()

        private static let normalBorderColor = UIColor.ows_gray45
        private static let highlightedBorderColor = UIColor.ows_gray45.withAlphaComponent(0.5)

        override init(frame: CGRect) {
            super.init(frame: frame)
            contentEdgeInsets = UIEdgeInsets(hMargin: 22, vMargin: 12)
            addSubview(backgroundPillView)
            sendSubviewToBack(backgroundPillView)
            backgroundPillView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(margin: 8))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var isHighlighted: Bool {
            didSet {
                backgroundPillView.layer.borderColor = (isHighlighted ? Self.highlightedBorderColor : Self.normalBorderColor).cgColor
            }
        }
    }
}

extension MediaTileViewController: MediaGalleryPrimaryViewController {

    typealias MenuItem = MediaGalleryAccessoriesHelper.MenuItem

    var scrollView: UIScrollView { return collectionView }

    var isFiltering: Bool {
        return mediaGallery.allowedMediaType != MediaGalleryFinder.MediaType.defaultMediaType(for: fileType)
    }

    var isEmpty: Bool {
        return mediaGallery.galleryDates.isEmpty
    }

    var hasSelection: Bool {
        if let count = collectionView.indexPathsForSelectedItems?.count, count > 0 {
            return true
        }
        return false
    }

    func selectionInfo() -> (count: Int, totalSize: Int64)? {
        guard
            let items = collectionView.indexPathsForSelectedItems?.compactMap({ galleryItem(at: $0) }),
            !items.isEmpty
        else {
            return nil
        }

        let totalSize = items.reduce(Int64(0), { result, item in result + Int64(item.attachmentStream.byteCount) })
        return (items.count, totalSize)
    }

    var mediaGalleryFilterMenuItems: [MediaGalleryAccessoriesHelper.MenuItem] {
        return [
            MenuItem(
                title:
                    OWSLocalizedString(
                        "ALL_MEDIA_FILTER_NONE",
                        comment: "Menu option to remove content type restriction in All Media view"
                    ),
                isChecked: mediaGallery.allowedMediaType == MediaGalleryFinder.MediaType.defaultMediaType(for: fileType),
                handler: { [weak self] in
                    self?.disableFiltering()
                }
            ),
            MenuItem(
                title:
                    OWSLocalizedString(
                        "ALL_MEDIA_FILTER_PHOTOS",
                        comment: "Menu option to limit All Media view to displaying only photos"
                    ),
                isChecked: mediaGallery.allowedMediaType == .photos,
                handler: { [weak self] in
                    self?.filter(.photos)
                }
            ),
            MenuItem(
                title:
                    OWSLocalizedString(
                        "ALL_MEDIA_FILTER_VIDEOS",
                        comment: "Menu option to limit All Media view to displaying only videos"
                    ),
                isChecked: mediaGallery.allowedMediaType == .videos,
                handler: { [weak self] in
                    self?.filter(.videos)
                }
            ),
            MenuItem(
                title:
                    OWSLocalizedString(
                        "ALL_MEDIA_FILTER_GIFS",
                        comment: "Menu option to limit All Media view to displaying only GIFs"
                    ),
                isChecked: mediaGallery.allowedMediaType == .gifs,
                handler: { [weak self] in
                    self?.filter(.gifs)
                }
            )
        ]
    }

    func disableFiltering() {
        let date: GalleryDate?
        if let indexPath = oldestVisibleIndexPath?.shiftingSection(by: -1) {
            date = mediaGallery.galleryDates[indexPath.section]
        } else {
            date = nil
        }
        let indexPathToScrollTo = mediaGallery.setAllowedMediaType(
            MediaGalleryFinder.MediaType.defaultMediaType(for: fileType),
            loadUntil: date ?? GalleryDate(date: .distantFuture),
            batchSize: kLoadBatchSize,
            firstVisibleIndexPath: oldestVisibleIndexPath.map { mediaGalleryIndexPath($0) }
        )

        if date == nil {
            if mediaGallery.galleryDates.isEmpty {
                _ = self.mediaGallery.loadEarlierSections(batchSize: kLoadBatchSize)
            }
            if eagerLoadingDidComplete {
                // Filtering removed everything so we must restart eager loading.
                eagerLoadingDidComplete = false
                eagerlyLoadMoreIfPossible()
            }
        }
        if let indexPath = indexPathToScrollTo {
            collectionView.scrollToItem(at: self.indexPath(indexPath),
                                        at: .top,
                                        animated: false)
        }

        accessoriesHelper.updateFooterBarState()
    }

    func batchSelectionModeDidChange(isInBatchSelectMode: Bool) {
        collectionView!.allowsMultipleSelection = isInBatchSelectMode
        updateVisibleCells()
    }

    func didEndSelectMode() {
        // deselect any selected
        collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false)}
    }

    func deleteSelectedItems() {
        guard let indexPaths = collectionView.indexPathsForSelectedItems else {
            owsFailDebug("indexPaths was unexpectedly nil")
            return
        }

        let items: [MediaGalleryItem] = indexPaths.compactMap { return self.galleryItem(at: $0) }
        guard items.count == indexPaths.count else {
            owsFailDebug("trying to delete an item that never loaded")
            return
        }

        let actionSheetTitle = String.localizedStringWithFormat(
            OWSLocalizedString(
                "MEDIA_GALLERY_DELETE_MEDIA_TITLE",
                tableName: "PluralAware",
                comment: "Title for confirmation prompt when deleting N items in All Media screen."
            ),
            indexPaths.count
        )
        let actionSheetMessage = OWSLocalizedString(
            "MEDIA_GALLERY_DELETE_MEDIA_BODY",
            comment: "Explanatory text displayed when deleting N items in All Media screen."
        )
        let toastText = String.localizedStringWithFormat(
            OWSLocalizedString(
                "MEDIA_GALLERY_DELETE_MEDIA_TOAST",
                tableName: "PluralAware",
                comment: "Toast displayed after successful deletion of N items in All Media screen."),
            indexPaths.count
        )

        let actionSheet = ActionSheetController(title: actionSheetTitle, message: actionSheetMessage)
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.deleteButton,
            style: .destructive,
            handler: { [self] _ in
                let galleryIndexPaths = indexPaths.map { self.mediaGalleryIndexPath($0) }
                self.mediaGallery.delete(items: items, atIndexPaths: galleryIndexPaths, initiatedBy: self)
                self.accessoriesHelper.endSelectMode()
                DispatchQueue.main.async {
                    self.presentToast(text: toastText, extraVInset: self.collectionView.contentInset.bottom)
                }
            }
        ))
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }

    func shareSelectedItems(_ sender: Any) {
        guard let indexPaths = collectionView.indexPathsForSelectedItems else {
            owsFailDebug("indexPaths was unexpectedly nil")
            return
        }

        let items: [TSAttachmentStream] = indexPaths.compactMap { return self.galleryItem(at: $0)?.attachmentStream }
        guard items.count == indexPaths.count else {
            owsFailDebug("trying to delete an item that never loaded")
            return
        }

        AttachmentSharing.showShareUI(for: items, sender: sender)
    }
}

private extension IndexSet {
    func shifted(startingAt index: Int? = nil, by amount: Int) -> IndexSet {
        var result = self
        result.shift(startingAt: index ?? self.first ?? 0, by: amount)
        return result
    }
}

private extension IndexPath {
    func shiftingSection(by delta: Int) -> IndexPath {
        return IndexPath(item: item, section: section + delta)
    }
}

private class MediaTileCollectionViewCell: PhotoGridViewCell, MediaGalleryCollectionViewCell {

    var item: MediaGalleryCellItem?

    func setAllowsMultipleSelection(_ allowed: Bool, animated: Bool) {
        allowsMultipleSelection = allowed
    }

    func configure(item: MediaGalleryCellItem, spoilerState: SpoilerRenderState) {
        self.item = item
        guard case .photoVideo(let mediaGalleryCellItemPhotoVideo) = item else {
            owsFailDebug("Invalid item.")
            return
        }
        super.configure(item: mediaGalleryCellItemPhotoVideo)
    }

    func indexPathDidChange(_ indexPath: IndexPath, itemCount: Int) { }
}
