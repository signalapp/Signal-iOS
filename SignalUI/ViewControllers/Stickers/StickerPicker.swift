//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

// MARK: - Delegate Protocols

public protocol StickerPacksToolbarDelegate: AnyObject {
    func presentManageStickersView()
}

public protocol StickerPickerPageViewDelegate: StickerPickerDelegate {
    func setItems(_ items: [StickerHorizontalListViewItem])
    func updateSelections(scrollToSelectedItem: Bool)
}

// MARK: - StickerPacksToolbar

class StickerPacksToolbar: UIStackView {
    private static let packCoverSize: CGFloat = 32
    private static let packCoverInset: CGFloat = 4
    private static let packCoverSpacing: CGFloat = 4
    private let forceDarkTheme: Bool
    lazy var packsCollectionView: StickerHorizontalListView = {
        let view = StickerHorizontalListView(
            cellSize: StickerPacksToolbar.packCoverSize,
            cellInset: StickerPacksToolbar.packCoverInset,
            spacing: StickerPacksToolbar.packCoverSpacing,
            forceDarkTheme: forceDarkTheme
        )

        view.contentInset = .zero
        view.autoSetDimension(.height, toSize: StickerPacksToolbar.packCoverSize + view.contentInset.top + view.contentInset.bottom)

        return view
    }()

    private lazy var manageButton: OWSButton = {
        let tintColor = forceDarkTheme ? Theme.darkThemeSecondaryTextAndIconColor : Theme.secondaryTextAndIconColor
        let button = OWSButton(imageName: "plus", tintColor: tintColor) { [weak self] in
            self?.delegate?.presentManageStickersView()
        }
        button.setContentHuggingHigh()
        button.setCompressionResistanceHigh()
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "manageButton")
        return button
    }()

    public weak var delegate: StickerPacksToolbarDelegate? {
        didSet {
            configureManageButton()
        }
    }

    init(forceDarkTheme: Bool = false) {
        self.forceDarkTheme = forceDarkTheme
        super.init(frame: .zero)
        populate()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func populate() {
        spacing = Self.packCoverSpacing
        axis = .horizontal
        alignment = .center
        layoutMargins = UIEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        isLayoutMarginsRelativeArrangement = true

        packsCollectionView.backgroundColor = .clear
        addArrangedSubview(packsCollectionView)
    }

    private func configureManageButton() {
        if delegate != nil {
            // Show manage button
            addArrangedSubview(manageButton)
        } else {
            // Hide manage button
            removeArrangedSubview(manageButton)
        }
    }
}

// MARK: - StickerPickerPageView

public class StickerPickerPageView: UIView {

    public private(set) weak var delegate: StickerPickerPageViewDelegate?

    private let forceDarkTheme: Bool

    private var stickerPacks = [StickerPack]()

    private var selectedStickerPack: StickerPack? {
        didSet {
            selectedPackChanged(oldSelectedPack: oldValue)
        }
    }

    public init(delegate: StickerPickerPageViewDelegate, forceDarkTheme: Bool = false) {
        self.delegate = delegate
        self.forceDarkTheme = forceDarkTheme

        super.init(frame: .zero)

        layoutMargins = .zero

        setupPaging()

        reloadStickers()

        // By default, show the "recent" stickers.
        assert(nil == selectedStickerPack)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.stickersOrPacksDidChange,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(keyboardFrameDidChange),
                                               name: UIResponder.keyboardDidChangeFrameNotification,
                                               object: nil)
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func wasPresented() {
        // If there are no recents, default to showing the first sticker pack.
        if currentPageCollectionView.stickerCount < 1 {
            updateSelectedStickerPack(stickerPacks.first)
        }

        updatePageConstraints()
    }

    private let reusableStickerViewCache = StickerViewCache(maxSize: 32)
    private func reloadStickers() {
        let oldStickerPacks = stickerPacks

        databaseStorage.read { (transaction) in
            self.stickerPacks = StickerManager.installedStickerPacks(transaction: transaction).sorted {
                $0.dateCreated > $1.dateCreated
            }
        }

        var items = [StickerHorizontalListViewItem]()
        items.append(StickerHorizontalListViewItemRecents(
            didSelectBlock: { [weak self] in
                self?.recentsButtonWasTapped()
            },
            isSelectedBlock: { [weak self] in
                self?.selectedStickerPack == nil
            },
            forceDarkTheme: forceDarkTheme
        ))
        items += stickerPacks.map { (stickerPack) in
            StickerHorizontalListViewItemSticker(
                stickerInfo: stickerPack.coverInfo,
                didSelectBlock: { [weak self] in
                    self?.updateSelectedStickerPack(stickerPack)
                },
                isSelectedBlock: { [weak self] in
                    self?.selectedStickerPack?.info == stickerPack.info
                },
                cache: reusableStickerViewCache
            )
        }
        delegate?.setItems(items)

        guard stickerPacks.count > 0 else {
            _ = resignFirstResponder()
            return
        }

        guard oldStickerPacks != stickerPacks else { return }

        // If the selected pack was uninstalled, select the first pack.
        if let selectedStickerPack = selectedStickerPack, !stickerPacks.contains(selectedStickerPack) {
            updateSelectedStickerPack(stickerPacks.first)
        }

        resetStickerPages()
    }

    // MARK: Events

    @objc
    func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        reloadStickers()
    }

    @objc
    func keyboardFrameDidChange() {
        Logger.verbose("")

        updatePageConstraints(ignoreScrollingState: true)
    }

    private func recentsButtonWasTapped() {
        AssertIsOnMainThread()

        Logger.verbose("")

        // nil is used for the recents special-case.
        updateSelectedStickerPack(nil)
    }

    private func updateSelectedStickerPack(_ stickerPack: StickerPack?, scrollToSelected: Bool = false) {
        selectedStickerPack = stickerPack
        delegate?.updateSelections(scrollToSelectedItem: scrollToSelected)
    }

    // MARK: Paging

    /// This array always includes three collection views, where the indices represent:
    /// 0 - Previous Page
    /// 1 - Current Page
    /// 2 - Next Page
    var stickerPackCollectionViews = [
        StickerPackCollectionView(),
        StickerPackCollectionView(),
        StickerPackCollectionView()
    ]
    private var stickerPackCollectionViewConstraints = [NSLayoutConstraint]()

    private var currentPageCollectionView: StickerPackCollectionView {
        return stickerPackCollectionViews[1]
    }

    private var nextPageCollectionView: StickerPackCollectionView {
        return stickerPackCollectionViews[2]
    }

    private var previousPageCollectionView: StickerPackCollectionView {
        return stickerPackCollectionViews[0]
    }

    private lazy var stickerPagingScrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.delegate = self
        scrollView.clipsToBounds = false
        return scrollView
    }()

    private var nextPageStickerPack: StickerPack? {
        // If we don't have a pack defined, the first pack is always up next
        guard let stickerPack = selectedStickerPack else { return stickerPacks.first }

        // If we don't have an index, or we're at the end of the array, recents is up next
        guard let index = stickerPacks.firstIndex(of: stickerPack), index < (stickerPacks.count - 1) else { return nil }

        // Otherwise, use the next pack in the array
        return stickerPacks[index + 1]
    }

    private var previousPageStickerPack: StickerPack? {
        // If we don't have a pack defined, the last pack is always previous
        guard let stickerPack = selectedStickerPack else { return stickerPacks.last }

        // If we don't have an index, or we're at the start of the array, recents is previous
        guard let index = stickerPacks.firstIndex(of: stickerPack), index > 0 else { return nil }

        // Otherwise, use the previous pack in the array
        return stickerPacks[index - 1]
    }

    private var pageWidth: CGFloat { return stickerPagingScrollView.frame.width }
    private var numberOfPages: CGFloat { return CGFloat(stickerPackCollectionViews.count) }
    private let pageSpacing: CGFloat = 40

    // These thresholds indicate the offset at which we update the next / previous page.
    // They're not exactly half way through the transition, to avoid us continuously
    // bouncing back and forth between pages.
    private var previousPageThreshold: CGFloat { return pageWidth * 0.45 }
    private var nextPageThreshold: CGFloat { return pageWidth + previousPageThreshold }

    private func setupPaging() {
        addSubview(stickerPagingScrollView)
        stickerPagingScrollView.autoPinHeightToSuperview()
        stickerPagingScrollView.autoPinEdge(toSuperviewMargin: .leading, withInset: -0.5 * pageSpacing)
        stickerPagingScrollView.autoPinEdge(toSuperviewMargin: .trailing, withInset: -0.5 * pageSpacing)

        let stickerPagesContainer = UIView()
        stickerPagingScrollView.addSubview(stickerPagesContainer)
        stickerPagesContainer.autoPinEdgesToSuperviewEdges()
        stickerPagesContainer.autoMatch(.height, to: .height, of: stickerPagingScrollView)
        stickerPagesContainer.autoMatch(.width, to: .width, of: stickerPagingScrollView, withMultiplier: numberOfPages)

        for (index, collectionView) in stickerPackCollectionViews.enumerated() {
            collectionView.backgroundColor = .clear
            collectionView.isDirectionalLockEnabled = true
            collectionView.stickerDelegate = self

            // We want the current page on top, to prevent weird
            // animations when we initially calculate our frame.
            if collectionView == currentPageCollectionView {
                stickerPagesContainer.addSubview(collectionView)
            } else {
                stickerPagesContainer.insertSubview(collectionView, at: 0)
            }

            collectionView.autoMatch(.width, to: .width, of: stickerPagingScrollView, withOffset: -pageSpacing)
            collectionView.autoMatch(.height, to: .height, of: stickerPagingScrollView)

            collectionView.autoPinEdge(toSuperviewEdge: .top)
            collectionView.autoPinEdge(toSuperviewEdge: .bottom)

            stickerPackCollectionViewConstraints.append(
                collectionView.autoPinEdge(toSuperviewEdge: .left, withInset: CGFloat(index) * pageWidth + 0.5 * pageSpacing)
            )
        }
    }

    private var pendingPageChangeUpdates: (() -> Void)?
    private func applyPendingPageChangeUpdates() {
        pendingPageChangeUpdates?()
        pendingPageChangeUpdates = nil
    }

    private func selectedPackChanged(oldSelectedPack: StickerPack?) {
        AssertIsOnMainThread()

        // We're paging backwards!
        if oldSelectedPack == nextPageStickerPack {
            // The previous page becomes the current page and the current page becomes
            // the next page. We have to load the new previous.

            stickerPackCollectionViews.insert(stickerPackCollectionViews.removeLast(), at: 0)
            stickerPackCollectionViewConstraints.insert(stickerPackCollectionViewConstraints.removeLast(), at: 0)

            pendingPageChangeUpdates = {
                self.previousPageCollectionView.showInstalledPackOrRecents(stickerPack: self.previousPageStickerPack)
            }

        // We're paging forwards!
        } else if oldSelectedPack == previousPageStickerPack {
            // The next page becomes the current page and the current page becomes
            // the previous page. We have to load the new next.

            stickerPackCollectionViews.append(stickerPackCollectionViews.removeFirst())
            stickerPackCollectionViewConstraints.append(stickerPackCollectionViewConstraints.removeFirst())

            pendingPageChangeUpdates = {
                self.nextPageCollectionView.showInstalledPackOrRecents(stickerPack: self.nextPageStickerPack)
            }

        // We didn't get here through paging, stuff probably changed. Reload all the things.
        } else {
            currentPageCollectionView.showInstalledPackOrRecents(stickerPack: selectedStickerPack)
            previousPageCollectionView.showInstalledPackOrRecents(stickerPack: previousPageStickerPack)
            nextPageCollectionView.showInstalledPackOrRecents(stickerPack: nextPageStickerPack)

            pendingPageChangeUpdates = nil
        }

        // If we're not currently scrolling, apply the page change updates immediately.
        if !isScrollingChange { applyPendingPageChangeUpdates() }

        updatePageConstraints()
    }

    private func resetStickerPages() {
        currentPageCollectionView.showInstalledPackOrRecents(stickerPack: selectedStickerPack)
        previousPageCollectionView.showInstalledPackOrRecents(stickerPack: previousPageStickerPack)
        nextPageCollectionView.showInstalledPackOrRecents(stickerPack: nextPageStickerPack)

        pendingPageChangeUpdates = nil

        updatePageConstraints()

        delegate?.updateSelections(scrollToSelectedItem: false)
    }

    private func updatePageConstraints(ignoreScrollingState: Bool = false) {
        // Setup the collection views in their page positions
        for (index, constraint) in stickerPackCollectionViewConstraints.enumerated() {
            constraint.constant = CGFloat(index) * pageWidth + 0.5 * pageSpacing
        }

        // Scrolling backwards
        if !ignoreScrollingState && stickerPagingScrollView.contentOffset.x <= previousPageThreshold {
            stickerPagingScrollView.contentOffset.x += pageWidth

        // Scrolling forward
        } else if !ignoreScrollingState && stickerPagingScrollView.contentOffset.x >= nextPageThreshold {
            stickerPagingScrollView.contentOffset.x -= pageWidth

        // Not moving forward or back, just scroll back to center so we can go forward and back again
        } else {
            stickerPagingScrollView.contentOffset.x = pageWidth
        }
    }

    // MARK: - Scroll state management

    /// Indicates that the user stopped actively scrolling, but
    /// we still haven't reached their final destination.
    private var isWaitingForDeceleration = false

    /// Indicates that the user started scrolling and we've yet
    /// to reach their final destination.
    private var isUserScrolling = false

    /// Indicates that we're currently changing pages due to a
    /// user initiated scroll action.
    private var isScrollingChange = false

    private func userStartedScrolling() {
        isWaitingForDeceleration = false
        isUserScrolling = true
    }

    private func userStoppedScrolling(waitingForDeceleration: Bool = false) {
        guard isUserScrolling else { return }

        if waitingForDeceleration {
            isWaitingForDeceleration = true
        } else {
            isWaitingForDeceleration = false
            isUserScrolling = false
        }
    }

    private func checkForPageChange() {
        // Ignore any page changes unless the user is triggering them.
        guard isUserScrolling else { return }

        isScrollingChange = true

        let offsetX = stickerPagingScrollView.contentOffset.x

        // Scrolled left a page
        if offsetX <= previousPageThreshold {
            updateSelectedStickerPack(previousPageStickerPack, scrollToSelected: true)

            // Scrolled right a page
        } else if offsetX >= nextPageThreshold {
            updateSelectedStickerPack(nextPageStickerPack, scrollToSelected: true)

            // We're about to cross the threshold into a new page, execute any pending updates.
            // We wait to execute these until we're sure we're going to cross over as it
            // can cause some UI jitter that interrupts scrolling.
        } else if offsetX >= pageWidth * 0.95 && offsetX <= pageWidth * 1.05 {
            applyPendingPageChangeUpdates()
        }

        isScrollingChange = false
    }
}

// MARK: UIScrollViewDelegate

extension StickerPickerPageView: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        checkForPageChange()
    }

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userStartedScrolling()
    }

    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        userStoppedScrolling(waitingForDeceleration: decelerate)
    }

    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userStoppedScrolling()
    }
}

extension StickerPickerPageView: StickerPackCollectionViewDelegate {
    public func didSelectSticker(stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")

        delegate?.didSelectSticker(stickerInfo: stickerInfo)
    }

    public var storyStickerConfiguration: StoryStickerConfiguration {
        delegate?.storyStickerConfiguration ?? .hide
    }

    public func stickerPreviewHostView() -> UIView? {
        AssertIsOnMainThread()

        return window
    }

    public func stickerPreviewHasOverlay() -> Bool {
        return true
    }
}

// MARK: - StickerViewCache

public class StickerViewCache {

    private typealias CacheType = LRUCache<StickerInfo, ThreadSafeCacheHandle<StickerReusableView>>
    private let backingCache: CacheType

    public init(maxSize: Int) {
        // Always use a nseMaxSize of zero.
        backingCache = LRUCache(maxSize: maxSize,
                                nseMaxSize: 0,
                                shouldEvacuateInBackground: true)
    }

    public func get(key: StickerInfo) -> StickerReusableView? {
        self.backingCache.get(key: key)?.value
    }

    public func set(key: StickerInfo, value: StickerReusableView) {
        self.backingCache.set(key: key, value: ThreadSafeCacheHandle(value))
    }

    public func remove(key: StickerInfo) {
        self.backingCache.remove(key: key)
    }

    public func clear() {
        self.backingCache.clear()
    }

    // MARK: NSCache Compatibility

    public func setObject(_ value: StickerReusableView, forKey key: StickerInfo) {
        set(key: key, value: value)
    }

    public func object(forKey key: StickerInfo) -> StickerReusableView? {
        self.get(key: key)
    }

    public func removeObject(forKey key: StickerInfo) {
        remove(key: key)
    }

    public func removeAllObjects() {
        clear()
    }
}
