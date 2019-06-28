//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol StickerKeyboardDelegate {
    func didSelectSticker(stickerInfo: StickerInfo)
    func presentManageStickersView()
    func rootViewSize() -> CGSize
}

// MARK: -

@objc
public class StickerKeyboard: UIStackView {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    // MARK: -

    @objc
    public weak var delegate: StickerKeyboardDelegate?

    private let headerView = UIStackView()

    private var stickerPacks = [StickerPack]()

    private var selectedStickerPack: StickerPack? {
        didSet {
            selectedPackChanged(oldSelectedPack: oldValue)
        }
    }

    @objc
    public required init() {
        super.init(frame: .zero)

        createSubviews()

        reloadStickers()

        // By default, show the "recent" stickers.
        assert(nil == selectedStickerPack)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.stickersOrPacksDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(orientationDidChange),
                                               name: UIDevice.orientationDidChangeNotification,
                                               object: UIDevice.current)
    }

    required public init(coder: NSCoder) {
        notImplemented()
    }

    // TODO: Tune this value.
    private let kDefaultKeyboardHeight: CGFloat = 300

    @objc
    public override var intrinsicContentSize: CGSize {
        // Never take up more than half of the root view's height.
        let rootViewSize = self.rootViewSize
        let maxKeyboardHeight = rootViewSize.height / 2
        return CGSize(width: 0, height: min(kDefaultKeyboardHeight, maxKeyboardHeight))
    }

    private var rootViewSize: CGSize {
        guard let delegate = delegate else {
            return .zero
        }
        return delegate.rootViewSize()
    }

    private func createSubviews() {
        axis = .vertical
        layoutMargins = .zero
        autoresizingMask = .flexibleHeight
        alignment = .fill

        addBackgroundView(withBackgroundColor: keyboardBackgroundColor)

        addArrangedSubview(headerView)

        populateHeaderView()

        setupPaging()
    }

    private var keyboardBackgroundColor: UIColor {
        return (Theme.isDarkThemeEnabled
            ? UIColor.ows_gray90
            : UIColor.ows_gray02)
    }

    @objc public func wasPresented() {
        // If there are no recents, default to showing the first sticker pack.
        if currentPageCollectionView.stickerCount < 1 {
            selectedStickerPack = stickerPacks.first
        }

        updatePageConstraints()
    }

    private func reloadStickers() {
        databaseStorage.read { (transaction) in
            self.stickerPacks = StickerManager.installedStickerPacks(transaction: transaction).sorted {
                $0.dateCreated > $1.dateCreated
            }
        }

        var items = [StickerHorizontalListViewItem]()
        items.append(StickerHorizontalListViewItemRecents(didSelectBlock: { [weak self] in
            self?.recentsButtonWasTapped()
            }, isSelectedBlock: { [weak self] in
                self?.selectedStickerPack == nil
        }))
        items += stickerPacks.map { (stickerPack) in
            StickerHorizontalListViewItemSticker(stickerInfo: stickerPack.coverInfo,
                                                 didSelectBlock: { [weak self] in
                                                    self?.selectedStickerPack = stickerPack
                }, isSelectedBlock: { [weak self] in
                    self?.selectedStickerPack?.info == stickerPack.info
            })
        }
        packsCollectionView.items = items

        guard stickerPacks.count > 0 else {
            selectedStickerPack = nil
            return
        }

        // Update paging to reflect any potentially new ordering of sticker packs
        selectedPackChanged(oldSelectedPack: nil)
    }

    private static let packCoverSize: CGFloat = 32
    private static let packCoverInset: CGFloat = 4
    private static let packCoverSpacing: CGFloat = 4
    private let packsCollectionView = StickerHorizontalListView(cellSize: StickerKeyboard.packCoverSize,
                                                                cellInset: StickerKeyboard.packCoverInset,
                                                                spacing: StickerKeyboard.packCoverSpacing)

    private func populateHeaderView() {
        headerView.spacing = StickerKeyboard.packCoverSpacing
        headerView.axis = .horizontal
        headerView.alignment = .center
        headerView.backgroundColor = keyboardBackgroundColor
        headerView.layoutMargins = UIEdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6)
        headerView.isLayoutMarginsRelativeArrangement = true

        if FeatureFlags.stickerSearch {
            let searchButton = buildHeaderButton("search-24") { [weak self] in
                self?.searchButtonWasTapped()
            }
            headerView.addArrangedSubview(searchButton)
            searchButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "searchButton")
        }

        packsCollectionView.backgroundColor = keyboardBackgroundColor
        headerView.addArrangedSubview(packsCollectionView)

        let manageButton = buildHeaderButton("plus-24") { [weak self] in
            self?.manageButtonWasTapped()
        }
        headerView.addArrangedSubview(manageButton)
        manageButton.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "manageButton")

        updateHeaderView()
    }

    private func buildHeaderButton(_ imageName: String, block: @escaping () -> Void) -> UIView {
        let button = OWSButton(imageName: imageName, tintColor: Theme.secondaryColor, block: block)
        button.setContentHuggingHigh()
        button.setCompressionResistanceHigh()
        return button
    }

    private func updateHeaderView() {
    }

    // MARK: Events

    @objc
    func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        reloadStickers()
        updateHeaderView()
    }

    @objc
    func orientationDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        invalidateIntrinsicContentSize()
    }

    private var isLayingoutSubviews = false
    public override func layoutSubviews() {
        isLayingoutSubviews = true

        let previousPageWidth = pageWidth
        super.layoutSubviews()

        // If the page width changed (probably an orientation change),
        // make sure we stay centered on the current pack.
        if previousPageWidth != pageWidth {
            updatePageConstraints(ignoreScrollingState: true)
        }

        isLayingoutSubviews = false
    }

    private func searchButtonWasTapped() {
        AssertIsOnMainThread()

        Logger.verbose("")

        // TODO:
    }

    private func recentsButtonWasTapped() {
        AssertIsOnMainThread()

        Logger.verbose("")

        // nil is used for the recents special-case.
        selectedStickerPack = nil
    }

    private func manageButtonWasTapped() {
        AssertIsOnMainThread()

        Logger.verbose("")

        delegate?.presentManageStickersView()
    }

    // MARK: - Paging

    /// This array always includes three collection views, where the indeces represent:
    /// 0 - Previous Page
    /// 1 - Current Page
    /// 2 - Next Page
    private var stickerPackCollectionViews = [
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

    private let stickerPagingScrollView = UIScrollView()

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

    // These thresholds indicate the offset at which we update the next / previous page.
    // They're not exactly half way through the transition, to avoid us continously
    // bouncing back and forth between pages.
    private var previousPageThreshold: CGFloat { return pageWidth * 0.45 }
    private var nextPageThreshold: CGFloat { return pageWidth + previousPageThreshold }

    private func setupPaging() {
        stickerPagingScrollView.isPagingEnabled = true
        stickerPagingScrollView.showsHorizontalScrollIndicator = false
        stickerPagingScrollView.isDirectionalLockEnabled = true
        stickerPagingScrollView.delegate = self
        addArrangedSubview(stickerPagingScrollView)
        stickerPagingScrollView.autoPinEdge(toSuperviewSafeArea: .left)
        stickerPagingScrollView.autoPinEdge(toSuperviewSafeArea: .right)

        let stickerPagesContainer = UIView()
        stickerPagingScrollView.addSubview(stickerPagesContainer)
        stickerPagesContainer.autoPinEdgesToSuperviewEdges()
        stickerPagesContainer.autoMatch(.height, to: .height, of: stickerPagingScrollView)
        stickerPagesContainer.autoMatch(.width, to: .width, of: stickerPagingScrollView, withMultiplier: numberOfPages)

        for (index, collectionView) in stickerPackCollectionViews.enumerated() {
            collectionView.backgroundColor = keyboardBackgroundColor
            collectionView.isDirectionalLockEnabled = true
            collectionView.stickerDelegate = self
            stickerPagesContainer.addSubview(collectionView)

            collectionView.autoMatch(.width, to: .width, of: stickerPagingScrollView)
            collectionView.autoMatch(.height, to: .height, of: stickerPagingScrollView)

            collectionView.autoPinEdge(toSuperviewEdge: .top)
            collectionView.autoPinEdge(toSuperviewEdge: .bottom)

            stickerPackCollectionViewConstraints.append(
                collectionView.autoPinEdge(toSuperviewEdge: .left, withInset: CGFloat(index) * pageWidth)
            )
        }

    }

    private func checkForPageChange() {
        // Ignore any page changes while we're laying out, as the content
        // offset will move about as the scrollView potentially resizes.
        guard !isLayingoutSubviews else { return }

        let offsetX = stickerPagingScrollView.contentOffset.x

        // Scrolled left a page
        if offsetX <= previousPageThreshold {
            selectedStickerPack = previousPageStickerPack

        // Scrolled right a page
        } else if offsetX >= nextPageThreshold {
            selectedStickerPack = nextPageStickerPack

        // We're about to cross the threshold into a new page, execute any pending updates.
        // We wait to execute these until we're sure we're going to cross over as it
        // can cause some UI jitter that interupts scrolling.
        } else if offsetX >= pageWidth * 0.95 && offsetX <= pageWidth * 1.05 {
            pendingPageChangeUpdates?()
            pendingPageChangeUpdates = nil
        }
    }

    private var pendingPageChangeUpdates: (() -> Void)?

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

        updatePageConstraints()

        // Update the selected pack in the top bar.
        packsCollectionView.updateSelections()
    }

    private func updatePageConstraints(ignoreScrollingState: Bool = false) {
        // Setup the collection views in their page positions
        for (index, constraint) in stickerPackCollectionViewConstraints.enumerated() {
            constraint.constant = CGFloat(index) * pageWidth
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
}

// MARK: -

extension StickerKeyboard: UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        checkForPageChange()
    }
}

extension StickerKeyboard: StickerPackCollectionViewDelegate {
    public func didTapSticker(stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")

        delegate?.didSelectSticker(stickerInfo: stickerInfo)
    }

    public func stickerPreviewHostView() -> UIView? {
        AssertIsOnMainThread()

        return window
    }

    public func stickerPreviewHasOverlay() -> Bool {
        return true
    }
}
