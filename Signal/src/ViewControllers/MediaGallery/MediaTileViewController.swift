//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

fileprivate extension IndexSet {
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

extension MediaTileViewController: MediaGalleryCollectionViewUpdaterDelegate {
    func indexSet(_ mediaGallerySectionIndexSet: MediaGallerySectionIndexSet) -> IndexSet {
        return mediaGallerySectionIndexSet.indexSet.shifted(by: 1)
    }

    func updaterDeleteSections(_ sections: MediaGallerySectionIndexSet) {
        collectionView?.deleteSections(self.indexSet(sections))
    }

    func updaterDeleteItems(at indexPaths: [MediaGalleryIndexPath]) {
        collectionView?.deleteItems(at: indexPaths.map {
            self.indexPath($0)
        })
    }

    func updaterInsertSections(_ sections: MediaGallerySectionIndexSet) {
        collectionView?.insertSections(self.indexSet(sections))
    }

    func updaterReloadItems(at indexPaths: [MediaGalleryIndexPath]) {
        collectionView?.reloadItems(at: indexPaths.map {
            self.indexPath($0)
        })
    }

    func updaterReloadSections(_ sections: MediaGallerySectionIndexSet) {
        collectionView?.reloadSections(self.indexSet(sections))
    }

    func updaterDidFinish(numberOfSectionsBefore: Int, numberOfSectionsAfter: Int) {
        Logger.debug("\(numberOfSectionsBefore) -> \(numberOfSectionsAfter)")
        owsAssert(numberOfSectionsAfter == mediaGallery.galleryDates.count)
        if numberOfSectionsBefore == 0 && numberOfSectionsAfter > 0 {
            // Adding a "load newer" section. It goes at the end.
            collectionView?.insertSections(IndexSet(integer: localSection(numberOfSectionsAfter)))
            accessoriesHelper.updateFooterBarState()
        } else if numberOfSectionsBefore > 0 && numberOfSectionsAfter == 0 {
            // Remove "load newer" section from the end.
            collectionView?.deleteSections(IndexSet(integer: 1))
            accessoriesHelper.updateFooterBarState()
        }
    }
}

public class MediaTileViewController: UICollectionViewController, MediaGalleryDelegate, UICollectionViewDelegateFlowLayout {
    private let thread: TSThread
    private let accessoriesHelper: MediaGalleryAccessoriesHelper
    private lazy var mediaGallery: MediaGallery = {
        let mediaGallery = MediaGallery(thread: thread)
        mediaGallery.addDelegate(self)
        return mediaGallery
    }()
    fileprivate let mediaTileViewLayout: MediaTileViewLayout

    /// This is used to avoid running two animations concurrently. It doesn't look good on iOS 16 (and probably all other versions).
    private var activeAnimationCount = 0

    public init(thread: TSThread, accessoriesHelper: MediaGalleryAccessoriesHelper) {
        self.thread = thread
        self.accessoriesHelper = accessoriesHelper
        let layout: MediaTileViewLayout = type(of: self).buildLayout()
        self.mediaTileViewLayout = layout

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
        let indexPathToScrollTo = mediaGallery.setAllowedMediaType(mediaType,
                                                                   loadUntil: maybeDate ?? GalleryDate(date: Date.distantPast),
                                                                   batchSize: kLoadBatchSize,
                                                                   firstVisibleIndexPath: oldestVisibleIndexPath.map { mediaGalleryIndexPath($0) })
        accessoriesHelper.footerBarState = .filtering
        if let indexPath = indexPathToScrollTo {
            // Scroll to approximately where you were before.
            collectionView.scrollToItem(at: self.indexPath(indexPath),
                                        at: .top,
                                        animated: false)
        }
        eagerLoadingDidComplete = false
        eagerlyLoadMoreIfPossible()
    }

    // MARK: View Lifecycle Overrides

    override public func viewDidLoad() {
        super.viewDidLoad()

        self.title = MediaStrings.allMedia

        guard let collectionView = self.collectionView else {
            owsFailDebug("collectionView was unexpectedly nil")
            return
        }

        collectionView.register(PhotoGridViewCell.self, forCellWithReuseIdentifier: PhotoGridViewCell.reuseIdentifier)
        collectionView.register(ThemeCollectionViewSectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: ThemeCollectionViewSectionHeader.reuseIdentifier)
        collectionView.register(MediaGalleryStaticHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier)

        collectionView.delegate = self

        // feels a bit weird to have content smashed all the way to the bottom edge.
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)

        accessoriesHelper.add(toView: self.view)

        self.mediaTileViewLayout.invalidateLayout()

        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme), name: .ThemeDidChange, object: nil)
    }

    override public func viewWillAppear(_ animated: Bool) {
        defer { super.viewWillAppear(animated) }

        // You must layout before mutating mediaGallery. Otherwise, MediaTileViewLayout.prepare() could be
        // called while processing an update. That will violate the exclusive access rules since it calls
        // (indirectly) into MediaGallerySections.
        self.view.layoutIfNeeded()

        if mediaGallery.galleryDates.isEmpty {
            _ = self.mediaGallery.loadEarlierSections(batchSize: kLoadBatchSize)
            if mediaGallery.galleryDates.isEmpty {
                // There must be no media.
                return
            }
            eagerlyLoadMoreIfPossible()
        }

        let lastSectionItemCount = mediaGallery.numberOfItemsInSection(mediaGallery.galleryDates.count - 1)
        self.collectionView.scrollToItem(at: IndexPath(item: lastSectionItemCount - 1,
                                                       section: mediaGallery.galleryDates.count),
                                         at: .bottom,
                                         animated: false)
    }

    override public func viewWillTransition(to size: CGSize,
                                            with coordinator: UIViewControllerTransitionCoordinator) {
        self.mediaTileViewLayout.invalidateLayout()
        super.viewWillTransition(to: size, with: coordinator)
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        self.updateLayout()
    }

    // MARK: Theme

    @objc
    func applyTheme() {
        accessoriesHelper.applyTheme()

        collectionView.backgroundColor = Theme.backgroundColor
    }

    // MARK: Orientation

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.defaultSupportedOrientations
    }

    // MARK: UICollectionViewDelegate

    private let scrollFlag = MediaTileScrollFlag()

    private var willDecelerate = false
    private var scrollingToTop = false

    override public func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        scrollingToTop = true
        return true
    }

    override public func scrollViewDidScrollToTop(_ scrollView: UIScrollView) {
        scrollingToTop = false
        showOrHideScrollFlag()
    }

    override public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        willDecelerate = decelerate
    }

    override public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        willDecelerate = false
        showOrHideScrollFlag()
    }

    private var scrollFlagShouldBeVisible = false

    override public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        self.autoLoadMoreIfNecessary()
        showOrHideScrollFlag()
        if scrollFlag.superview != nil {
            updateScrollFlag()
        }
    }

    private func showOrHideScrollFlag() {
        if #unavailable(iOS 12) {
            return
        }
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
        if #unavailable(iOS 12) {
            return
        }
        guard mediaGallery.galleryDates.count > 0,
              let indexPath = reallyVisibleIndexPaths.min() else {
            scrollFlag.alpha = 0.0
            return
        }
        let i = mediaGallerySection(indexPath.section)
        let date = mediaGallery.galleryDates[i]
        scrollFlag.stringValue = date.localizedString
        scrollFlag.sizeToFit()

        scrollFlag.center = guessCenterOfFlag()
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
                if collectionView.scrollIndicatorInsets.bottom > 0 {
                    // Footer height takes precedence over adjustedContentInset, which is not terribly accurate.
                    result.bottom = collectionView.scrollIndicatorInsets.bottom
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
                if collectionView.scrollIndicatorInsets.bottom > 0 {
                    // Footer height takes precedence over adjustedContentInset, which is not terribly accurate.
                    result.bottom = collectionView.scrollIndicatorInsets.bottom
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

    var previousAdjustedContentInset: UIEdgeInsets = UIEdgeInsets()

    override public func scrollViewDidChangeAdjustedContentInset(_ scrollView: UIScrollView) {
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

    override public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {

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

    override public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {

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

    public override func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {

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

    override public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.info("")

        guard let gridCell = self.collectionView(collectionView, cellForItemAt: indexPath) as? PhotoGridViewCell else {
            owsFailDebug("galleryCell was unexpectedly nil")
            return
        }

        guard let galleryItem = (gridCell.item as? GalleryGridCellItem)?.galleryItem else {
            owsFailDebug("galleryItem was unexpectedly nil")
            return
        }

        if accessoriesHelper.isInBatchSelectMode {
            accessoriesHelper.didModifySelection()
        } else {
            collectionView.deselectItem(at: indexPath, animated: true)

            let pageVC = MediaPageViewController(
                initialMediaAttachment: galleryItem.attachmentStream,
                mediaGallery: mediaGallery
            )
            present(pageVC, animated: true)
        }
    }

    public override func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        Logger.debug("")

        accessoriesHelper.didModifySelection()
    }

    // MARK: UICollectionViewDataSource

    override public func numberOfSections(in collectionView: UICollectionView) -> Int {
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

    override public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
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

    override public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {

        let defaultView = UICollectionReusableView()

        guard !mediaGallery.galleryDates.isEmpty else {
            guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: MediaGalleryStaticHeader.reuseIdentifier, for: indexPath) as? MediaGalleryStaticHeader else {

                owsFailDebug("unable to build section header for kLoadOlderSectionIdx")
                return defaultView
            }
            let title = NSLocalizedString("GALLERY_TILES_EMPTY_GALLERY", comment: "Label indicating media gallery is empty")
            sectionHeader.configure(title: title)
            return sectionHeader
        }

        if kind == UICollectionView.elementKindSectionHeader {
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
                guard let sectionHeader = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: ThemeCollectionViewSectionHeader.reuseIdentifier, for: indexPath) as? ThemeCollectionViewSectionHeader else {
                    owsFailDebug("unable to build section header for indexPath: \(indexPath)")
                    return defaultView
                }
                guard let date = mediaGallery.galleryDates[safe: mediaGallerySection(indexPath.section)] else {
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

        guard let cell = self.collectionView?.dequeueReusableCell(withReuseIdentifier: PhotoGridViewCell.reuseIdentifier, for: indexPath) as? PhotoGridViewCell else {
            owsFailDebug("unexpected cell for indexPath: \(indexPath)")
            return UICollectionViewCell()
        }

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

            let gridCellItem = GalleryGridCellItem(galleryItem: galleryItem)
            VideoDurationHelper.shared.with(context: videoDurationContext) {
                cell.configure(item: gridCellItem)
            }
        }
        return cell
    }

    private lazy var videoDurationContext = { VideoDurationHelper.Context() }()

    override public func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        guard let photoGridViewCell = cell as? PhotoGridViewCell else {
            owsFailDebug("unexpected cell: \(cell)")
            return
        }

        photoGridViewCell.allowsMultipleSelection = collectionView.allowsMultipleSelection
    }

    func galleryItem(at indexPath: IndexPath, loadAsync: Bool = false) -> MediaGalleryItem? {
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

    func updateVisibleCells() {
        for cell in collectionView.visibleCells {
            guard let photoGridViewCell = cell as? PhotoGridViewCell else {
                owsFailDebug("unexpected cell: \(cell)")
                continue
            }

            photoGridViewCell.allowsMultipleSelection = collectionView.allowsMultipleSelection
        }
    }

    // MARK: UICollectionViewDelegateFlowLayout

    static let kInterItemSpacing: CGFloat = 2
    private class func buildLayout() -> MediaTileViewLayout {
        let layout = MediaTileViewLayout()

        layout.sectionInsetReference = .fromSafeArea
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing
        if #available(iOS 12, *) {
            // Modern design
            layout.sectionHeadersPinToVisibleBounds = false
        } else {
            // Legacy design, which I can't test easily.
            layout.sectionHeadersPinToVisibleBounds = true
        }

        return layout
    }

    func updateLayout() {
        let rawSize = view.safeAreaLayoutGuide.layoutFrame.size

        let containerSize = CGSize(width: floor(rawSize.width), height: floor(rawSize.height))

        let kItemsPerPortraitRow = 4
        let minimumViewWidth = min(containerSize.width, containerSize.height)
        let approxItemWidth = minimumViewWidth / CGFloat(kItemsPerPortraitRow)

        let itemCount = round(containerSize.width / approxItemWidth)
        let interSpaceWidth = (itemCount - 1) * type(of: self).kInterItemSpacing
        let availableWidth = max(0, containerSize.width - interSpaceWidth)

        let itemWidth = floor(availableWidth / CGFloat(itemCount))
        let newItemSize = CGSize(square: itemWidth)
        let remainingSpace = availableWidth - (itemCount * itemWidth)
        let hInset = remainingSpace / 2
        if newItemSize != mediaTileViewLayout.itemSize || hInset != mediaTileViewLayout.sectionInset.left {
            mediaTileViewLayout.itemSize = newItemSize
            // Inset any remaining space around the outside edges to ensure all inter-item spacing is exactly equal, otherwise
            // we may get slightly different gaps between rows vs. columns
            mediaTileViewLayout.sectionInset = UIEdgeInsets(top: 0, leading: hInset, bottom: 0, trailing: hInset)
            mediaTileViewLayout.invalidateLayout()
        }
    }

    public func collectionView(_ collectionView: UICollectionView,
                               layout collectionViewLayout: UICollectionViewLayout,
                               referenceSizeForHeaderInSection section: Int) -> CGSize {

        let kMonthHeaderSize: CGSize = CGSize(width: 0, height: 50)
        let kStaticHeaderSize: CGSize = CGSize(width: 0, height: 100)

        guard !mediaGallery.galleryDates.isEmpty else {
            return kStaticHeaderSize
        }

        switch section {
        case kLoadOlderSectionIdx:
            // Show "loading older..." iff there is still older data to be fetched
            return mediaGallery.hasFetchedOldest ? CGSize.zero : kStaticHeaderSize
        case loadNewerSectionIdx:
            // Show "loading newer..." iff there is still more recent data to be fetched
            return mediaGallery.hasFetchedMostRecent ? CGSize.zero : kStaticHeaderSize
        default:
            return kMonthHeaderSize
        }
    }

    // MARK: MediaGalleryDelegate

    func mediaGallery(_ mediaGallery: MediaGallery,
                      applyUpdate update: MediaGallery.Update) {
        Logger.debug("Will begin batch update. animating=\(activeAnimationCount)")
        let shouldAnimate = activeAnimationCount == 0 && !update.userData.contains(where: { $0.disableAnimations })

        let saved = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(shouldAnimate && UIView.areAnimationsEnabled && saved)

        if update.userData.contains(where: { $0.shouldRecordContentSizeBeforeInsertingToTop }) {
            mediaTileViewLayout.recordContentSizeBeforeInsertingToTop()
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
        // If you receive a new attachment for an earlier month, MediaGallerySections resets itself and throws out a bunch of data. It resets hasFetched{Oldest,MostRecent} to false. This causes "Loading older…" and "Loading newer…" to become visible, even if there are no older or newer months in the db. Those only get updated on scroll. If the collection view's content size is less than its visible size then scrolling is impossible and they are stuck forever. Load sections until we either have everything or there's enough room for the user to scroll.
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

    // MARK: Lazy Loading

    var isFetchingMoreData = false
    let kLoadBatchSize: Int = 100

    let kLoadOlderSectionIdx: Int = 0
    var loadNewerSectionIdx: Int {
        return localSection(mediaGallery.galleryDates.count)
    }
    private var eagerLoadingDidComplete = false

    private func eagerlyLoadMoreIfPossible() {
        Logger.debug("")
        guard !mediaGallery.hasFetchedOldest else {
            Logger.debug("done")
            eagerLoadingDidComplete = true
            return
        }
        let userData = MediaGalleryUpdateUserData(disableAnimations: true,
                                                  shouldRecordContentSizeBeforeInsertingToTop: true)
        // This is a low priority update because we never want eager loads to starve user-initiated
        // loads (such as loading more sections because of scrolling or loading items to display).
        mediaGallery.asyncLoadEarlierSections(batchSize: kLoadBatchSize,
                                              highPriority: false,
                                              userData: userData) { [weak self] newSections in
            Logger.debug("Eagerly loaded \(newSections)")
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

        guard let cell = collectionView.visibleCells[safe: visibleIndex] as? PhotoGridViewCell else {
            owsFailDebug("cell was unexpectedly nil")
            return nil
        }

        let mediaView = cell.imageView

        guard let mediaSuperview = mediaView.superview else {
            owsFailDebug("mediaSuperview was unexpectedly nil")
            return nil
        }

        let presentationFrame = coordinateSpace.convert(mediaView.frame, from: mediaSuperview)
        let clippingAreaInsets = UIEdgeInsets(top: collectionView.adjustedContentInset.top, leading: 0, bottom: 0, trailing: 0)

        return MediaPresentationContext(
            mediaView: mediaView,
            presentationFrame: presentationFrame,
            clippingAreaInsets: clippingAreaInsets
        )
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return nil
    }
}

// MARK: - Private Helper Classes

// Accommodates remaining scrolled to the same "apparent" position when new content is inserted
// into the top of a collectionView. There are multiple ways to solve this problem, but this
// is the only one which avoided a perceptible flicker.
private class MediaTileViewLayout: UICollectionViewFlowLayout {
    private var contentSizeBeforeInsertingToTop: CGSize?

    func recordContentSizeBeforeInsertingToTop() {
        contentSizeBeforeInsertingToTop = collectionViewContentSize
    }

    override public func prepare() {
        super.prepare()

        if let collectionView = collectionView, let oldContentSize = contentSizeBeforeInsertingToTop {
            let newContentSize = collectionViewContentSize
            collectionView.contentOffset.y += newContentSize.height - oldContentSize.height
            contentSizeBeforeInsertingToTop = nil
        }
    }
}

private class MediaGalleryStaticHeader: UICollectionViewCell {

    static let reuseIdentifier = "MediaGalleryStaticHeader"

    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_dynamicTypeBody
        addSubview(label)

        label.textAlignment = .center
        label.numberOfLines = 0
        label.autoPinEdgesToSuperviewMargins()
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func configure(title: String) {
        label.text = title
    }

    public override func prepareForReuse() {
        label.text = nil
        label.textColor = Theme.primaryTextColor
        label.font = UIFont.ows_dynamicTypeBody
    }
}

class GalleryGridCellItem: PhotoGridItem {
    let galleryItem: MediaGalleryItem

    init(galleryItem: MediaGalleryItem) {
        self.galleryItem = galleryItem
    }

    var type: PhotoGridItemType {
        if galleryItem.isVideo {
            return .video(videoDurationPromise)
        } else if galleryItem.isAnimated {
            return .animated
        } else {
            return .photo
        }
    }

    var creationDate: Date? { nil }

    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) -> UIImage? {
        return galleryItem.thumbnailImage(async: completion)
    }

    private var videoDurationPromise: Promise<TimeInterval> {
        owsAssert(galleryItem.isVideo)
        return VideoDurationHelper.shared.promisedDuration(attachment: galleryItem.attachmentStream)
    }
}

extension MediaTileViewController: MediaGalleryPrimaryViewController {
    typealias MenuAction = MediaGalleryAccessoriesHelper.MenuAction

    var isFiltering: Bool {
        return mediaGallery.allowedMediaType != nil
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

    var mediaGalleryFilterMenuActions: [MediaGalleryAccessoriesHelper.MenuAction] {
        return [
            MenuAction(
                title:
                    OWSLocalizedString(
                        "ALL_MEDIA_FILTER_PHOTOS",
                        comment: "Menu option to limit All Media view to displaying only photos"),
                icon: UIImage(named: "all-media-filter-photos"),
                handler: { [weak self] in
                    self?.filter(.photos)
                }),
            MenuAction(
                title:
                    OWSLocalizedString(
                        "ALL_MEDIA_FILTER_VIDEOS",
                        comment: "Menu option to limit All Media view to displaying only videos"),
                icon: UIImage(named: "all-media-filter-videos"),
                handler: { [weak self] in
                    self?.filter(.videos)
                }),
            MenuAction(
                title:
                    OWSLocalizedString(
                        "ALL_MEDIA_FILTER_GIFS",
                        comment: "Menu option to limit All Media view to displaying only GIFs"),
                icon: UIImage(named: "all-media-filter-gifs"),
                handler: { [weak self] in
                    self?.filter(.gifs)
                })
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
            nil,
            loadUntil: date ?? GalleryDate(date: .distantFuture),
            batchSize: kLoadBatchSize,
            firstVisibleIndexPath: oldestVisibleIndexPath.map { mediaGalleryIndexPath($0) })

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

        let format = NSLocalizedString("MEDIA_GALLERY_DELETE_MESSAGES_%d", tableName: "PluralAware",
                                       comment: "Confirmation button text to delete selected media message(s) from the gallery")
        let confirmationTitle = String.localizedStringWithFormat(format, indexPaths.count)

        let deleteAction = ActionSheetAction(title: confirmationTitle, style: .destructive) { _ in
            let galleryIndexPaths = indexPaths.map { self.mediaGalleryIndexPath($0) }
            self.mediaGallery.delete(items: items, atIndexPaths: galleryIndexPaths, initiatedBy: self)
            self.accessoriesHelper.endSelectMode()
        }

        let actionSheet = ActionSheetController(title: nil, message: nil)
        actionSheet.addAction(deleteAction)
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

        AttachmentSharing.showShareUI(forAttachments: items, sender: sender)
    }
}
