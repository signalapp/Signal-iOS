// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import QuartzCore
import GRDB
import DifferenceKit
import SessionUIKit
import SignalUtilitiesKit

public class MediaTileViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    
    /// This should be larger than one screen size so we don't have to call it multiple times in rapid succession, but not
    /// so large that loading get's really chopping
    static let itemPageSize: Int = Int(11 * itemsPerPortraitRow)
    static let itemsPerPortraitRow: CGFloat = 4
    static let interItemSpacing: CGFloat = 2
    static let footerBarHeight: CGFloat = 40
    static let loadMoreHeaderHeight: CGFloat = 100
    
    public let viewModel: MediaGalleryViewModel
    private var hasLoadedInitialData: Bool = false
    private var didFinishInitialLayout: Bool = false
    private var isAutoLoadingNextPage: Bool = false
    private var currentTargetOffset: CGPoint?
    
    public var delegate: MediaTileViewControllerDelegate?
    
    var isInBatchSelectMode = false {
        didSet {
            collectionView.allowsMultipleSelection = isInBatchSelectMode
            updateSelectButton(updatedData: self.viewModel.galleryData, inBatchSelectMode: isInBatchSelectMode)
            updateDeleteButton()
        }
    }
    
    // MARK: - Initialization

    init(viewModel: MediaGalleryViewModel) {
        self.viewModel = viewModel
        Storage.shared.addObserver(viewModel.pagedDataObserver)

        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - UI
    
    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .allButUpsideDown
    }
    
    var footerBarBottomConstraint: NSLayoutConstraint?

    fileprivate lazy var mediaTileViewLayout: MediaTileViewLayout = {
        let result: MediaTileViewLayout = MediaTileViewLayout()
        result.sectionInsetReference = .fromSafeArea
        result.minimumInteritemSpacing = MediaTileViewController.interItemSpacing
        result.minimumLineSpacing = MediaTileViewController.interItemSpacing
        result.sectionHeadersPinToVisibleBounds = true

        return result
    }()
    
    lazy var collectionView: UICollectionView = {
        let result: UICollectionView = UICollectionView(frame: .zero, collectionViewLayout: mediaTileViewLayout)
        result.translatesAutoresizingMaskIntoConstraints = false
        result.themeBackgroundColor = .backgroundSecondary
        result.delegate = self
        result.dataSource = self
        result.register(view: PhotoGridViewCell.self)
        result.register(view: MediaGallerySectionHeader.self, ofKind: UICollectionView.elementKindSectionHeader)
        result.register(view: MediaGalleryStaticHeader.self, ofKind: UICollectionView.elementKindSectionHeader)
        
        // Feels a bit weird to have content smashed all the way to the bottom edge.
        result.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        
        return result
    }()

    lazy var footerBar: UIToolbar = {
        let result: UIToolbar = UIToolbar()
        result.setItems(
            [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil),
                deleteButton,
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            ],
            animated: false
        )

        result.themeBarTintColor = .backgroundPrimary
        result.themeTintColor = .textPrimary

        return result
    }()

    lazy var deleteButton: UIBarButtonItem = {
        let result: UIBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .trash,
            target: self,
            action: #selector(didPressDelete)
        )
        result.themeTintColor = .textPrimary

        return result
    }()

    // MARK: - Lifecycle
    
    override public func viewDidLoad() {
        super.viewDidLoad()
        
        view.themeBackgroundColor = .backgroundSecondary

        // Add a custom back button if this is the only view controller
        if self.navigationController?.viewControllers.first == self {
            let backButton = UIViewController.createOWSBackButton(target: self, selector: #selector(didPressDismissButton))
            self.navigationItem.leftBarButtonItem = backButton
        }
        
        ViewControllerUtilities.setUpDefaultSessionStyle(
            for: self,
            title: MediaStrings.allMedia,
            hasCustomBackButton: false
        )

        view.addSubview(self.collectionView)
        collectionView.autoPin(toEdgesOf: view)
        
        view.addSubview(self.footerBar)
        footerBar.autoPinWidthToSuperview()
        footerBar.autoSetDimension(.height, toSize: MediaTileViewController.footerBarHeight)
        self.footerBarBottomConstraint = footerBar.autoPinEdge(toSuperviewEdge: .bottom, withInset: -MediaTileViewController.footerBarHeight)

        self.updateSelectButton(updatedData: self.viewModel.galleryData, inBatchSelectMode: false)
        self.mediaTileViewLayout.invalidateLayout()
        
        // Notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidResignActive(_:)),
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        startObservingChanges()
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.didFinishInitialLayout = true
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        stopObservingChanges()
    }
    
    @objc func applicationDidBecomeActive(_ notification: Notification) {
        startObservingChanges(didReturnFromBackground: true)
    }
    
    @objc func applicationDidResignActive(_ notification: Notification) {
        stopObservingChanges()
    }

    override public func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        self.mediaTileViewLayout.invalidateLayout()
    }

    public override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        
        self.updateLayout()
    }
    
    // MARK: - Updating
    
    private func performInitialScrollIfNeeded() {
        // Ensure this hasn't run before and that we have data (The 'galleryData' will always
        // contain something as the 'empty' state is a section within 'galleryData')
        guard !self.didFinishInitialLayout && self.hasLoadedInitialData else { return }
        
        // If we have a focused item then we want to scroll to it
        guard let focusedIndexPath: IndexPath = self.viewModel.focusedIndexPath else { return }
        
        Logger.debug("scrolling to focused item at indexPath: \(focusedIndexPath)")
        
        // Note: For some reason 'scrollToItem' doesn't always work properly so we need to manually
        // calculate what the offset should be to do the initial scroll
        self.view.layoutIfNeeded()
        
        let availableHeight: CGFloat = {
            // Note: This height will be set before we have properly performed a layout and fitted
            // this screen within it's parent UIPagedViewController so we need to try to calculate
            // the "actual" height of the collection view
            var finalHeight: CGFloat = self.collectionView.frame.height
            
            if let navController: UINavigationController = self.parent?.navigationController {
                finalHeight -= navController.navigationBar.frame.height
                finalHeight -= (UIApplication.shared.keyWindow?.windowScene?.statusBarManager?.statusBarFrame.height ?? 0)
            }
            
            if let tabBar: TabBar = self.parent?.parent?.view.subviews.first as? TabBar {
                finalHeight -= tabBar.frame.height
            }
            
            return finalHeight
        }()
        let focusedRect: CGRect = (self.collectionView.layoutAttributesForItem(at: focusedIndexPath)?.frame)
            .defaulting(to: .zero)
        self.collectionView.contentOffset = CGPoint(
            x: 0,
            y: (focusedRect.origin.y - (availableHeight / 2) + (focusedRect.height / 2))
        )
        self.collectionView.collectionViewLayout.invalidateLayout()
        
        // Now that the data has loaded we need to check if either of the "load more" sections are
        // visible and trigger them if so
        //
        // Note: We do it this way as we want to trigger the load behaviour for the first section
        // if it has one before trying to trigger the load behaviour for the last section
        self.autoLoadNextPageIfNeeded()
    }
    
    private func autoLoadNextPageIfNeeded() {
        guard !self.isAutoLoadingNextPage else { return }
        
        self.isAutoLoadingNextPage = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + PagedData.autoLoadNextPageDelay) { [weak self] in
            self?.isAutoLoadingNextPage = false
            
            // Note: We sort the headers as we want to prioritise loading newer pages over older ones
            let sortedVisibleIndexPaths: [IndexPath] = (self?.collectionView
                .indexPathsForVisibleSupplementaryElements(ofKind: UICollectionView.elementKindSectionHeader))
                .defaulting(to: [])
                .sorted()
            
            for headerIndexPath in sortedVisibleIndexPaths {
                let section: MediaGalleryViewModel.SectionModel? = self?.viewModel.galleryData[safe: headerIndexPath.section]
                
                switch section?.model {
                    case .loadNewer, .loadOlder:
                        // Attachments are loaded in descending order so 'loadOlder' actually corresponds with
                        // 'pageAfter' in this case
                        self?.viewModel.pagedDataObserver?.load(section?.model == .loadOlder ?
                            .pageAfter :
                            .pageBefore
                        )
                        return
                        
                    default: continue
                }
            }
        }
    }
    
    private func startObservingChanges(didReturnFromBackground: Bool = false) {
        // Start observing for data changes (will callback on the main thread)
        self.viewModel.onGalleryChange = { [weak self] updatedGalleryData in
            self?.handleUpdates(updatedGalleryData)
        }
        
        // Note: When returning from the background we could have received notifications but the
        // PagedDatabaseObserver won't have them so we need to force a re-fetch of the current
        // data to ensure everything is up to date
        if didReturnFromBackground {
            self.viewModel.pagedDataObserver?.reload()
        }
    }
    
    private func stopObservingChanges() {
        // Note: The 'pagedDataObserver' will continue to get changes but
        // we don't want to trigger any UI updates
        self.viewModel.onGalleryChange = nil
    }
    
    private func handleUpdates(_ updatedGalleryData: [MediaGalleryViewModel.SectionModel]) {
        // Ensure the first load runs without animations (if we don't do this the cells will animate
        // in from a frame of CGRect.zero)
        guard hasLoadedInitialData else {
            self.hasLoadedInitialData = true
            self.viewModel.updateGalleryData(updatedGalleryData)
            self.updateSelectButton(updatedData: updatedGalleryData, inBatchSelectMode: isInBatchSelectMode)
            
            UIView.performWithoutAnimation {
                self.collectionView.reloadData()
                self.performInitialScrollIfNeeded()
            }
            return
        }
        
        // Determine if we are inserting content at the top of the collectionView
        let isInsertingAtTop: Bool = {
            let oldFirstSectionIsLoadMore: Bool = (
                self.viewModel.galleryData.first?.model == .loadNewer ||
                self.viewModel.galleryData.first?.model == .loadOlder
            )
            let oldTargetSectionIndex: Int = (oldFirstSectionIsLoadMore ? 1 : 0)
            
            guard
                let newTargetSectionIndex = updatedGalleryData
                    .firstIndex(where: { $0.model == self.viewModel.galleryData[safe: oldTargetSectionIndex]?.model }),
                let oldFirstItem: MediaGalleryViewModel.Item = self.viewModel.galleryData[safe: oldTargetSectionIndex]?.elements.first,
                let newFirstItemIndex = updatedGalleryData[safe: newTargetSectionIndex]?.elements.firstIndex(of: oldFirstItem)
            else { return false }
            
            return (newTargetSectionIndex > oldTargetSectionIndex || newFirstItemIndex > 0)
        }()
        
        // We want to maintain the same content offset between the updates if content was added to
        // the top, the mediaTileViewLayout will adjust content offset to compensate for the change
        // in content height so that the same content is visible after the update
        //
        // Using the `CollectionViewLayout.prepare` approach (rather than calling setContentOffset
        // in the batchUpdate completion block) avoids a distinct flicker (we also have to
        // disable animations for this to avoid buggy animations)
        CATransaction.begin()
        
        if isInsertingAtTop { CATransaction.setDisableActions(true) }
        
        self.mediaTileViewLayout.isInsertingCellsToTop = isInsertingAtTop
        self.mediaTileViewLayout.contentSizeBeforeInsertingToTop = self.collectionView.contentSize
        self.collectionView.reload(
            using: StagedChangeset(source: self.viewModel.galleryData, target: updatedGalleryData),
            interrupt: { $0.changeCount > MediaTileViewController.itemPageSize }
        ) { [weak self] updatedData in
            self?.viewModel.updateGalleryData(updatedData)
        }
        
        CATransaction.setCompletionBlock { [weak self] in
            // Need to manually reset these here as the 'reload' method above can actually trigger
            // multiple updates (eg. inserting sections and then items)
            self?.mediaTileViewLayout.isInsertingCellsToTop = false
            self?.mediaTileViewLayout.contentSizeBeforeInsertingToTop = nil
            
            // If one of the "load more" sections is still visible once the animation completes then
            // trigger another "load more" (after a small delay to minimize animation bugginess)
            self?.autoLoadNextPageIfNeeded()
        }
        CATransaction.commit()
        
        // Update the select button (should be hidden if there is no data)
        self.updateSelectButton(updatedData: updatedGalleryData, inBatchSelectMode: isInBatchSelectMode)
    }
    
    // MARK: - Interactions
    
    @objc public func didPressDismissButton() {
        let presentedNavController: UINavigationController? = (self.presentingViewController as? UINavigationController)
        let mediaPageViewController: MediaPageViewController? = (
            (presentedNavController?.viewControllers.last as? MediaPageViewController) ??
            (self.presentingViewController as? MediaPageViewController)
        )
        
        // If the album was presented from a 'MediaPageViewController' and it has no more data (ie.
        // all album items had been deleted) then dismiss to the screen before that one
        guard mediaPageViewController?.viewModel.albumData.isEmpty != true else {
            presentedNavController?.presentingViewController?.dismiss(animated: true, completion: nil)
            return
        }
        
        dismiss(animated: true, completion: nil)
    }
    
    // MARK: - UIScrollViewDelegate
    
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        self.currentTargetOffset = nil
    }
    
    public func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        self.currentTargetOffset = targetContentOffset.pointee
    }
    
    // MARK: - UICollectionViewDataSource

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return self.viewModel.galleryData.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let section: MediaGalleryViewModel.SectionModel = self.viewModel.galleryData[section]
        
        return section.elements.count
    }

    public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let section: MediaGalleryViewModel.SectionModel = self.viewModel.galleryData[indexPath.section]
        
        switch section.model {
            case .emptyGallery, .loadOlder, .loadNewer:
                let sectionHeader: MediaGalleryStaticHeader = collectionView.dequeue(type: MediaGalleryStaticHeader.self, ofKind: kind, for: indexPath)
                sectionHeader.configure(
                    title: {
                        switch section.model {
                            case .emptyGallery: return "GALLERY_TILES_EMPTY_GALLERY".localized()
                            case .loadOlder: return "GALLERY_TILES_LOADING_OLDER_LABEL".localized()
                            case .loadNewer: return "GALLERY_TILES_LOADING_MORE_RECENT_LABEL".localized()
                            case .galleryMonth: return ""   // Impossible case
                        }
                    }()
                )
                
                return sectionHeader
                
            case .galleryMonth(let date):
                let sectionHeader: MediaGallerySectionHeader = collectionView.dequeue(type: MediaGallerySectionHeader.self, ofKind: kind, for: indexPath)
                sectionHeader.configure(
                    title: date.localizedString
                )
                
                return sectionHeader
        }
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let section: MediaGalleryViewModel.SectionModel = self.viewModel.galleryData[indexPath.section]
        let cell: PhotoGridViewCell = collectionView.dequeue(type: PhotoGridViewCell.self, for: indexPath)
        cell.configure(
            item: GalleryGridCellItem(
                galleryItem: section.elements[indexPath.row]
            )
        )

        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, willDisplaySupplementaryView view: UICollectionReusableView, forElementKind elementKind: String, at indexPath: IndexPath) {
        // Want to ensure the initial content load has completed before we try to load any more data
        guard self.didFinishInitialLayout else { return }
        
        let section: MediaGalleryViewModel.SectionModel = self.viewModel.galleryData[indexPath.section]
        
        switch section.model {
            case .loadOlder, .loadNewer:
                UIScrollView.fastEndScrollingThen(collectionView, self.currentTargetOffset) { [weak self] in
                    // Attachments are loaded in descending order so 'loadOlder' actually corresponds with
                    // 'pageAfter' in this case
                    self?.viewModel.pagedDataObserver?.load(section.model == .loadOlder ?
                        .pageAfter :
                        .pageBefore
                    )
                }
                
            case .emptyGallery, .galleryMonth: break
        }
    }

    // MARK: - UICollectionViewDelegate

    public func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        let section: MediaGalleryViewModel.Section = self.viewModel.galleryData[indexPath.section].model

        switch section {
            case .emptyGallery, .loadOlder, .loadNewer: return false
            case .galleryMonth: return true
        }
    }

    public func collectionView(_ collectionView: UICollectionView, shouldDeselectItemAt indexPath: IndexPath) -> Bool {
        let section: MediaGalleryViewModel.Section = self.viewModel.galleryData[indexPath.section].model

        switch section {
            case .emptyGallery, .loadOlder, .loadNewer: return false
            case .galleryMonth: return true
        }
    }

    public func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        let section: MediaGalleryViewModel.Section = self.viewModel.galleryData[indexPath.section].model

        switch section {
            case .emptyGallery, .loadOlder, .loadNewer: return false
            case .galleryMonth: return true
        }
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let section: MediaGalleryViewModel.SectionModel = self.viewModel.galleryData[indexPath.section]
        
        switch section.model {
            case .emptyGallery, .loadOlder, .loadNewer: return
            case .galleryMonth: break
        }
        
        guard !isInBatchSelectMode else {
            updateDeleteButton()
            return
        }
        
        collectionView.deselectItem(at: indexPath, animated: true)
        
        let galleryItem: MediaGalleryViewModel.Item = section.elements[indexPath.row]
        
        // First check if this screen was presented
        guard let presentingViewController: UIViewController = self.presentingViewController else {
            // If we got to the gallery via conversation settings, present the detail view
            // on top of the tile view
            //
            // == ViewController Schematic ==
            //
            // [DetailView] <--,
            // [TileView] -----'
            // [ConversationSettingsView]
            // [ConversationView]
            //
            let detailViewController: UIViewController? = MediaGalleryViewModel.createDetailViewController(
                for: self.viewModel.threadId,
                threadVariant: self.viewModel.threadVariant,
                interactionId: galleryItem.interactionId,
                selectedAttachmentId: galleryItem.attachment.id,
                options: [ .sliderEnabled ]
            )
            
            guard let detailViewController: UIViewController = detailViewController else { return }
            
            delegate?.presentdetailViewController(detailViewController, animated: true)
            return
        }
        
        // Check if we were presented via the 'MediaPageViewController'
        guard let existingDetailPageView: MediaPageViewController = (presentingViewController as? UINavigationController)?.viewControllers.first as? MediaPageViewController else {
            self.navigationController?.dismiss(animated: true)
            return
        }
        
        // If we got to the gallery via the conversation view, pop the tile view
        // to return to the detail view
        //
        // == ViewController Schematic ==
        //
        // [TileView] -----,
        // [DetailView] <--'
        // [ConversationView]
        //
        existingDetailPageView.setCurrentItem(galleryItem, direction: .forward, animated: false)
        existingDetailPageView.willBePresentedAgain()
        self.viewModel.updateFocusedItem(attachmentId: galleryItem.attachment.id, indexPath: indexPath)
        self.navigationController?.dismiss(animated: true)
    }

    public func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        if isInBatchSelectMode {
            updateDeleteButton()
        }
    }

    // MARK: - UICollectionViewDelegateFlowLayout
    
    func updateLayout() {
        let screenWidth: CGFloat = min(UIScreen.main.bounds.width, UIScreen.main.bounds.height)
        let approxItemWidth: CGFloat = (screenWidth / MediaTileViewController.itemsPerPortraitRow)
        let itemSectionInsets: UIEdgeInsets = self.collectionView(
            collectionView,
            layout: mediaTileViewLayout,
            insetForSectionAt: 1
        )
        let widthInset: CGFloat = (itemSectionInsets.left + itemSectionInsets.right)
        let containerWidth: CGFloat = (collectionView.frame.width > CGFloat.leastNonzeroMagnitude ?
            collectionView.frame.width :
            view.bounds.width
        )
        let collectionViewWidth: CGFloat = (containerWidth - widthInset)
        let itemCount: CGFloat = round(collectionViewWidth / approxItemWidth)
        let spaceWidth: CGFloat = ((itemCount - 1) * MediaTileViewController.interItemSpacing)
        let availableWidth: CGFloat = (collectionViewWidth - spaceWidth)
        
        let itemWidth = floor(availableWidth / CGFloat(itemCount))
        let newItemSize = CGSize(width: itemWidth, height: itemWidth)

        if newItemSize != mediaTileViewLayout.itemSize {
            mediaTileViewLayout.itemSize = newItemSize
            mediaTileViewLayout.invalidateLayout()
        }
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return .zero
    }

    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        let section: MediaGalleryViewModel.SectionModel = self.viewModel.galleryData[section]
        
        switch section.model {
            case .emptyGallery, .loadOlder, .loadNewer:
                return CGSize(width: 0, height: MediaTileViewController.loadMoreHeaderHeight)
            
            case .galleryMonth: return CGSize(width: 0, height: 50)
        }
    }

    // MARK: Batch Selection

    func updateDeleteButton() {
        self.deleteButton.isEnabled = ((collectionView.indexPathsForSelectedItems?.count ?? 0) > 0)
    }

    func updateSelectButton(updatedData: [MediaGalleryViewModel.SectionModel], inBatchSelectMode: Bool) {
        delegate?.updateSelectButton(updatedData: updatedData, inBatchSelectMode: inBatchSelectMode)
    }

    @objc func didTapSelect(_ sender: Any) {
        isInBatchSelectMode = true

        // show toolbar
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut, animations: { [weak self] in
            self?.footerBarBottomConstraint?.isActive = false
            self?.footerBarBottomConstraint = self?.footerBar.autoPinEdge(toSuperviewSafeArea: .bottom)
            self?.footerBar.superview?.layoutIfNeeded()

            // Ensure toolbar doesn't cover bottom row.
            self?.collectionView.contentInset.bottom += MediaTileViewController.footerBarHeight
        }, completion: nil)
    }

    @objc func didCancelSelect(_ sender: Any) {
        endSelectMode()
    }

    func endSelectMode() {
        isInBatchSelectMode = false

        // hide toolbar
        UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseInOut, animations: { [weak self] in
            self?.footerBarBottomConstraint?.isActive = false
            self?.footerBarBottomConstraint = self?.footerBar.autoPinEdge(toSuperviewEdge: .bottom, withInset: -MediaTileViewController.footerBarHeight)
            self?.footerBar.superview?.layoutIfNeeded()

            // Undo "Ensure toolbar doesn't cover bottom row."
            self?.collectionView.contentInset.bottom -= MediaTileViewController.footerBarHeight
        }, completion: nil)

        // Deselect any selected
        collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: false)}
    }

    @objc func didPressDelete(_ sender: Any) {
        guard let indexPaths = collectionView.indexPathsForSelectedItems else {
            owsFailDebug("indexPaths was unexpectedly nil")
            return
        }

        let items: [MediaGalleryViewModel.Item] = indexPaths.map {
            self.viewModel.galleryData[$0.section].elements[$0.item]
        }
        let confirmationTitle: String = {
            if indexPaths.count == 1 {
                return "MEDIA_GALLERY_DELETE_SINGLE_MESSAGE".localized()
            }
            
            return String(
                format: "MEDIA_GALLERY_DELETE_MULTIPLE_MESSAGES_FORMAT".localized(),
                indexPaths.count
            )
        }()

        let deleteAction = UIAlertAction(title: confirmationTitle, style: .destructive) { [weak self] _ in
            Storage.shared.writeAsync { db in
                let interactionIds: Set<Int64> = items
                    .map { $0.interactionId }
                    .asSet()
                
                _ = try Attachment
                    .filter(ids: items.map { $0.attachment.id })
                    .deleteAll(db)
                
                // Add the garbage collection job to delete orphaned attachment files
                JobRunner.add(
                    db,
                    job: Job(
                        variant: .garbageCollection,
                        behaviour: .runOnce,
                        details: GarbageCollectionJob.Details(
                            typesToCollect: [.orphanedAttachmentFiles]
                        )
                    )
                )
                
                // Delete any interactions which had all of their attachments removed
                _ = try Interaction
                    .filter(ids: interactionIds)
                    .having(Interaction.interactionAttachments.isEmpty)
                    .deleteAll(db)
            }
            
            self?.endSelectMode()
        }

        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        actionSheet.addAction(deleteAction)
        actionSheet.addAction(OWSAlerts.cancelAction)

        presentAlert(actionSheet)
    }
}

// MARK: - Private Helper Classes

// Accomodates remaining scrolled to the same "apparent" position when new content is inserted
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
                
                // Update the content size in case there is a subsequent update
                contentSizeBeforeInsertingToTop = newContentSize
            }
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
            return AlwaysOnTopLayer.self
        }
    }

    override init(frame: CGRect) {
        label = UILabel()
        label.themeTextColor = .textPrimary

        super.init(frame: frame)

        self.themeBackgroundColor = .clear
        
        let backgroundView: UIView = UIView()
        backgroundView.themeBackgroundColor = .backgroundSecondary
        addSubview(backgroundView)
        backgroundView.pin(to: self)

        self.addSubview(label)
        label.pin(.leading, to: .leading, of: self, withInset: Values.largeSpacing)
        label.pin(.trailing, to: .trailing, of: self, withInset: -Values.largeSpacing)
        label.center(.vertical, in: self)
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

        label.themeTextColor = .textPrimary
        label.textAlignment = .center
        label.numberOfLines = 0
        label.autoPinEdgesToSuperviewMargins(with: UIEdgeInsets(top: 0, leading: Values.largeSpacing, bottom: 0, trailing: Values.largeSpacing))
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

class GalleryGridCellItem: PhotoGridItem {
    let galleryItem: MediaGalleryViewModel.Item

    init(galleryItem: MediaGalleryViewModel.Item) {
        self.galleryItem = galleryItem
    }

    var type: PhotoGridItemType {
        if galleryItem.isVideo {
            return .video
        }
        
        if galleryItem.isAnimated {
            return .animated
        }
        
        return .photo
    }

    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) {
        galleryItem.thumbnailImage(async: completion)
    }
}

// MARK: - UIViewControllerTransitioningDelegate

extension MediaTileViewController: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard
            self == presented ||
            self.navigationController == presented ||
            self.parent == presented ||
            self.parent?.navigationController == presented
        else { return nil }
        guard let focusedIndexPath: IndexPath = self.viewModel.focusedIndexPath else { return nil }

        return MediaDismissAnimationController(
            galleryItem: self.viewModel.galleryData[focusedIndexPath.section].elements[focusedIndexPath.item]
        )
    }

    public func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard
            self == dismissed ||
            self.navigationController == dismissed ||
            self.parent == dismissed ||
            self.parent?.navigationController == dismissed
        else { return nil }
        guard let focusedIndexPath: IndexPath = self.viewModel.focusedIndexPath else { return nil }

        return MediaZoomAnimationController(
            galleryItem: self.viewModel.galleryData[focusedIndexPath.section].elements[focusedIndexPath.item],
            shouldBounce: false
        )
    }
}

// MARK: - MediaPresentationContextProvider

extension MediaTileViewController: MediaPresentationContextProvider {
    func mediaPresentationContext(mediaItem: Media, in coordinateSpace: UICoordinateSpace) -> MediaPresentationContext? {
        guard case let .gallery(galleryItem) = mediaItem else { return nil }

        // Note: According to Apple's docs the 'indexPathsForVisibleRows' method returns an
        // unsorted array which means we can't use it to determine the desired 'visibleCell'
        // we are after, due to this we will need to iterate all of the visible cells to find
        // the one we want
        let maybeGridCell: PhotoGridViewCell? = collectionView.visibleCells
            .first { cell -> Bool in
                guard
                    let cell: PhotoGridViewCell = cell as? PhotoGridViewCell,
                    let item: GalleryGridCellItem = cell.item as? GalleryGridCellItem,
                    item.galleryItem.attachment.id == galleryItem.attachment.id
                else { return false }
                
                return true
            }
            .map { $0 as? PhotoGridViewCell }
        
        guard
            let gridCell: PhotoGridViewCell = maybeGridCell,
            let mediaSuperview: UIView = gridCell.imageView.superview
        else { return nil }
        
        let presentationFrame: CGRect = coordinateSpace.convert(gridCell.imageView.frame, from: mediaSuperview)
        
        return MediaPresentationContext(
            mediaView: gridCell.imageView,
            presentationFrame: presentationFrame,
            cornerRadius: 0,
            cornerMask: CACornerMask()
        )
    }

    func snapshotOverlayView(in coordinateSpace: UICoordinateSpace) -> (UIView, CGRect)? {
        return self.navigationController?.navigationBar.generateSnapshot(in: coordinateSpace)
    }
}

// MARK: - MediaTileViewControllerDelegate

public protocol MediaTileViewControllerDelegate: AnyObject {
    func presentdetailViewController(_ detailViewController: UIViewController, animated: Bool)
    func updateSelectButton(updatedData: [MediaGalleryViewModel.SectionModel], inBatchSelectMode: Bool)
}
