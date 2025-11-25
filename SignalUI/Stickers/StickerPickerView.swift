//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

protocol StickerPickerViewDelegate: StickerPickerDelegate {

    func presentManageStickersView(for: StickerPickerView)
}

class StickerPickerView: UIView {

    weak var delegate: StickerPickerViewDelegate?
    private let storyStickerConfigation: StoryStickerConfiguration

    var stickerPackCollectionViewPages: [UICollectionView] {
        stickerPageView.stickerPackCollectionViews
    }

    init(
        delegate: StickerPickerViewDelegate,
        storyStickerConfiguration: StoryStickerConfiguration = .hide
    ) {
        self.delegate = delegate
        self.storyStickerConfigation = storyStickerConfiguration

        super.init(frame: .zero)

        addSubview(stickerPageView)
        stickerPageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stickerPageView.topAnchor.constraint(equalTo: topAnchor),
            stickerPageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stickerPageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stickerPageView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        addSubview(toolbar)
        toolbar.preservesSuperviewLayoutMargins = true
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if #available(iOS 26, *) {
            let interaction = UIScrollEdgeElementContainerInteraction()
            interaction.edge = .bottom
            interaction.scrollView = stickerPageView.scrollViewForScrollEdgeElementContainerInteraction
            toolbar.addInteraction(interaction)
        }

        updateStickerPageViewContentInsets()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Presentation

    func willBePresented() {
        stickerPageView.willBePresented()
    }

    func wasPresented() {
        stickerPageView.wasPresented()
    }

    // MARK: Layout

    private lazy var toolbar = StickerPacksToolbar(delegate: self)
    private lazy var stickerPageView = StickerPickerPageView(
        delegate: self,
        storyStickerConfiguration: storyStickerConfigation
    )

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        updateStickerPageViewContentInsets()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Necessary to update bottom inset after footer has its final position and size.
        DispatchQueue.main.async {
            self.updateStickerPageViewBottomContentInset()
        }
    }

    // Leading, top and trailing insets are derived from view's layout margins.
    private func updateStickerPageViewContentInsets() {
        var contentInset = stickerPageView.stickerPageContentInset
        contentInset.top = layoutMargins.top - safeAreaInsets.top
        contentInset.leading = layoutMargins.leading - safeAreaInsets.leading
        contentInset.trailing = layoutMargins.trailing - safeAreaInsets.trailing
        stickerPageView.stickerPageContentInset = contentInset
    }

    // Update bottom inset separately - it depends on size and position of the toolbar.
    private func updateStickerPageViewBottomContentInset() {
        guard toolbar.frame.height > 0 else { return }
        let bottomInset = safeAreaLayoutGuide.layoutFrame.maxY - toolbar.frame.minY
        stickerPageView.stickerPageContentInset.bottom = bottomInset
    }
}

extension StickerPickerView: StickerPacksToolbarDelegate {

    fileprivate func presentManageStickersView(for toolbar: StickerPacksToolbar) {
        delegate?.presentManageStickersView(for: self)
    }
}

extension StickerPickerView: StickerPickerPageViewDelegate {

    func setItems(_ items: [any StickerHorizontalListViewItem]) {
        toolbar.packsCollectionView.items = items
    }

    func updateSelections(scrollToSelectedItem: Bool) {
        toolbar.packsCollectionView.updateSelections(scrollToSelectedItem: scrollToSelectedItem)
    }

    func didSelectSticker(_ stickerInfo: StickerInfo) {
        delegate?.didSelectSticker(stickerInfo)
    }
}

// MARK: - StickerPacksToolbar

private protocol StickerPacksToolbarDelegate: AnyObject {

    func presentManageStickersView(for: StickerPacksToolbar)
}

/// Designed to be pinned to the bottom edge of the screen, stretched to leading and trailing edges of the view.
/// Toolbar will inherit superview's leading and trailing margins and will use them for content layout.
private class StickerPacksToolbar: UIView {

    weak var delegate: StickerPacksToolbarDelegate? {
        didSet {
            configureManageButton()
        }
    }

    init(delegate: StickerPacksToolbarDelegate) {
        self.delegate = delegate

        super.init(frame: .zero)

        directionalLayoutMargins = .zero

        //
        // Content layout is different on iOS 26 vs previous versions.
        // See below for layout explanation.
        //
        if #available(iOS 26, *) {
            // Glass capsule-shaped panel on iOS 26+.
            let glassEffect = UIGlassEffect(style: .regular)
            // Copied from ConversationInputToolbar.
            glassEffect.tintColor = UIColor { traitCollection in
                if traitCollection.userInterfaceStyle == .dark {
                    return UIColor(white: 0, alpha: 0.2)
                }
                return UIColor(white: 1, alpha: 0.12)
            }
            let glassEffectView = UIVisualEffectView(effect: glassEffect)
            glassEffectView.clipsToBounds = true
            glassEffectView.cornerConfiguration = .capsule()

            glassEffectView.contentView.addSubview(stackView)
            addSubview(glassEffectView)

            visualEffectView = glassEffectView
        }
        // Blur on earlier iOS versions, but only if "Reduce Transparency" is disabled.
        else if UIAccessibility.isReduceTransparencyEnabled.negated {
            let blurEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))

            blurEffectView.contentView.addSubview(stackView)
            addSubview(blurEffectView)

            visualEffectView = blurEffectView
        } else {
            // Basically the same layout as above, but with no blur effect view.

            backgroundColor = .Signal.background

            addSubview(stackView)
        }

        configureManageButton()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        invalidateIntrinsicContentSize()
    }

    // MARK: - Layout

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        cachedHeight = 0
    }

    override var intrinsicContentSize: CGSize {
        calculateHeightIfNeeded()
        return CGSize(width: UIView.noIntrinsicMetric, height: cachedHeight)
    }

    private var cachedHeight: CGFloat = 0

    private func calculateHeightIfNeeded() {
        guard cachedHeight == 0 else { return }

        // Collection view height is the base.
        var height: CGFloat = Metrics.collectionViewHeight

        if #available(iOS 26, *) {
            // Vertical padding to glass container's vertical edges.
            height += 2 * Metrics.listVMargin

            // Bottom padding
            height += bottomContentMargin
        } else {
            // Padding above the sticker list.
            height += Metrics.listVMargin

            // Bottom padding
            height += bottomContentMargin
        }

        cachedHeight = height
    }

    private var bottomContentMargin: CGFloat {
        // Use non-zero padding on devices with the home button that doesn't have bottom safe area inset.
        safeAreaInsets.bottom == 0 ? Metrics.minimumBottomMargin : safeAreaInsets.bottom
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if #available(iOS 26, *) {
            layoutSubviewsForGlassBackground()
        } else {
            layoutSubviewsForBlurBackground()
        }
    }

    @available(iOS 26, *)
    private func layoutSubviewsForGlassBackground() {
        guard let visualEffectView else {
            owsFailBeta("No glass view")
            return
        }

        var sideMargin: CGFloat = 0
        var glassPanelWidth: CGFloat = 0
        if safeAreaInsets.totalWidth == 0 {
            // No left/right safe areas insets - use same amount as bottom padding.
            sideMargin = bottomContentMargin
            glassPanelWidth = bounds.width - 2 * sideMargin
        } else {
            // Non-zero left/right safe area margins - constrain width to safe area.
            sideMargin = safeAreaInsets.left
            glassPanelWidth = bounds.width - safeAreaInsets.totalWidth
        }
        visualEffectView.frame = CGRect(
            x: sideMargin,
            y: 0,
            width: glassPanelWidth,
            height: Metrics.collectionViewHeight + 2 * Metrics.listVMargin
        )

        // Content is inset from glass panel's edges by the same amount on all sides.
        stackView.frame = visualEffectView.contentView.bounds.inset(by: .init(margin: Metrics.listVMargin))
    }

    @available(iOS, deprecated: 26)
    private func layoutSubviewsForBlurBackground() {
        // Blur, if present, covers the whole view.
        if let visualEffectView {
            visualEffectView.frame = bounds
        }

        // Use left/right layout margins as side margins (they include safe area insets).
        stackView.frame = CGRect(
            x: layoutMargins.left,
            y: Metrics.listVMargin,
            width: bounds.width - layoutMargins.totalWidth,
            height: Metrics.collectionViewHeight
        )
    }

    private enum Metrics {
        static let listItemCellSize: CGFloat = 40 // side of each collection view cell.
        static let listItemContentInset: CGFloat = 8 // how much cell's content is inset from cell's edges.
        static let listItemSpacing: CGFloat = 4 // between cells

        static let listVMargin: CGFloat = 4 // spacing above and below collection view
        static let minimumBottomMargin: CGFloat = 8 // for devices with no bottom safe area

        static var collectionViewHeight: CGFloat { listItemCellSize }
    }

    // Glass on iOS 26+, blur or nothing on iOS 15-18.
    private var visualEffectView: UIVisualEffectView?

    // [scrollable list ][manage button]
    private lazy var stackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [ packsCollectionView, buttonManageStickers ])
        stackView.axis = .horizontal
        stackView.spacing = Metrics.listItemSpacing
        return stackView
    }()

    lazy var packsCollectionView: StickerHorizontalListView = {
        StickerHorizontalListView(
            cellSize: Metrics.listItemCellSize,
            cellContentInset: Metrics.listItemContentInset,
            spacing: Metrics.listItemSpacing
        )
    }()

    private lazy var buttonManageStickers: UIButton = {
        let button = UIButton(
            configuration: .plain(),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.delegate?.presentManageStickersView(for: self)
            }
        )
        if #available(iOS 26, *) {
            button.configuration?.cornerStyle = .capsule
        } else {
            button.configuration?.cornerStyle = .fixed
        }
        button.tintColor = .Signal.label
        button.configuration?.image = UIImage(named: "plus") // 24 dp
        button.configuration?.contentInsets = .init(margin: 8) // makes 40 dp button
        button.setContentHuggingHigh()
        button.setCompressionResistanceHigh()
        button.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: "manageButton")
        return button
    }()

    private func configureManageButton() {
        buttonManageStickers.isHidden = (delegate == nil)
    }
}

// MARK: - StickerPickerPageView

private protocol StickerPickerPageViewDelegate: StickerPickerDelegate {

    func setItems(_ items: [StickerHorizontalListViewItem])

    func updateSelections(scrollToSelectedItem: Bool)
}

private class StickerPickerPageView: UIView {

    private weak var delegate: StickerPickerPageViewDelegate?

    private let storyStickerConfiguration: StoryStickerConfiguration

    private var stickerPacks = [StickerPack]()

    private var selectedStickerPack: StickerPack? {
        didSet {
            selectedPackChanged(oldSelectedPack: oldValue)
        }
    }

    init(
        delegate: StickerPickerPageViewDelegate,
        storyStickerConfiguration: StoryStickerConfiguration = .hide
    ) {
        self.delegate = delegate
        self.storyStickerConfiguration = storyStickerConfiguration

        super.init(frame: .zero)

        setupPaging()
        reloadStickers()

        // By default, show the "recent" stickers.
        assert(nil == selectedStickerPack)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.stickersOrPacksDidChange,
                                               object: nil)
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func willBePresented() {
        // If there are no recents, default to showing the first sticker pack.
        if currentPageCollectionView.stickerCount < 1 {
            updateSelectedStickerPack(stickerPacks.first)
        }
    }

    func wasPresented() {
        updatePageConstraints(ignoreScrollingState: true)
    }

    override var bounds: CGRect {
        didSet {
            guard bounds.width != oldValue.width else { return }
            updatePageConstraints(ignoreScrollingState: true)
        }
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        updateStickerPageContentInset()
    }

    var stickerPageContentInset: UIEdgeInsets = .zero {
        didSet {
            updateStickerPageContentInset()
        }
    }

    @available(iOS 26, *)
    var scrollViewForScrollEdgeElementContainerInteraction: UIScrollView {
        stickerPagingScrollView
    }

    private func updateStickerPageContentInset() {
        var contentInset = stickerPageContentInset
        // Paging scroll view uses whole screen width - otherwise paging would look broken.
        // But each page must respect left and right safe areas when displaying content.
        contentInset.leading += safeAreaInsets.leading
        contentInset.trailing += safeAreaInsets.trailing
        // On the bottom there's usually a sticker pack toolbar which defines the bottom inset.
        // To make sure content doesn't go too close to the toolbar we increase the bottom margin.
        // However, scroll indicator should go all the way down.
        contentInset.bottom += 8
        for stickerPackCollectionView in stickerPackCollectionViews {
            stickerPackCollectionView.contentInset = contentInset
            stickerPackCollectionView.verticalScrollIndicatorInsets.bottom = stickerPageContentInset.bottom
        }
    }

    private let reusableStickerViewCache = StickerViewCache(maxSize: 32)

    private func reloadStickers() {
        let oldStickerPacks = stickerPacks

        SSKEnvironment.shared.databaseStorageRef.read { (transaction) in
            self.stickerPacks = StickerManager.installedStickerPacks(transaction: transaction).sorted {
                $0.dateCreated > $1.dateCreated
            }
        }

        // These go (via delegate) as source data to the toolbar.
        // No need to reverse order because toolbar supports mirrored layout for RTL languages.
        var items = [StickerHorizontalListViewItem]()
        items.append(StickerHorizontalListViewItemRecents(
            didSelectBlock: { [weak self] in
                self?.recentsButtonWasTapped()
            },
            isSelectedBlock: { [weak self] in
                self?.selectedStickerPack == nil
            }
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

        // Simply reverse sticker packs for RTL languages.
        if traitCollection.layoutDirection == .rightToLeft {
            stickerPacks = stickerPacks.reversed()
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
    private func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        reloadStickers()
    }

    private func recentsButtonWasTapped() {
        AssertIsOnMainThread()

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
    lazy var stickerPackCollectionViews: [StickerPackCollectionView] = [
        StickerPackCollectionView(storyStickerConfiguration: storyStickerConfiguration),
        StickerPackCollectionView(storyStickerConfiguration: storyStickerConfiguration),
        StickerPackCollectionView(storyStickerConfiguration: storyStickerConfiguration),
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
        scrollView.contentInsetAdjustmentBehavior = .never
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

    // These thresholds indicate the offset at which we update the next / previous page.
    // They're not exactly half way through the transition, to avoid us continuously
    // bouncing back and forth between pages.
    private var previousPageThreshold: CGFloat { return pageWidth * 0.45 }

    private var nextPageThreshold: CGFloat { return pageWidth + previousPageThreshold }

    private func setupPaging() {
        // Horizontally scrolling paging scroll view is stretched to view's bounds.
        stickerPagingScrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stickerPagingScrollView)
        NSLayoutConstraint.activate([
            stickerPagingScrollView.topAnchor.constraint(equalTo: topAnchor),
            stickerPagingScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stickerPagingScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stickerPagingScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Wide container that has several pages next to each other and is inside of the paging scroll view.
        let stickerPagesContainer = UIView()
        stickerPagesContainer.translatesAutoresizingMaskIntoConstraints = false
        stickerPagingScrollView.addSubview(stickerPagesContainer)
        NSLayoutConstraint.activate([
            // Pin all edges to scroll view's content layout guide.
            stickerPagesContainer.topAnchor.constraint(
                equalTo: stickerPagingScrollView.contentLayoutGuide.topAnchor
            ),
            stickerPagesContainer.leadingAnchor.constraint(
                equalTo: stickerPagingScrollView.contentLayoutGuide.leadingAnchor
            ),
            stickerPagesContainer.trailingAnchor.constraint(
                equalTo: stickerPagingScrollView.contentLayoutGuide.trailingAnchor
            ),
            stickerPagesContainer.bottomAnchor.constraint(
                equalTo: stickerPagingScrollView.contentLayoutGuide.bottomAnchor
            ),

            // Height must be equal to height of `stickerPagingScrollView`.
            stickerPagesContainer.heightAnchor.constraint(
                equalTo: stickerPagingScrollView.frameLayoutGuide.heightAnchor
            ),

            // Width is width of `stickerPagingScrollView` * number of pages.
            stickerPagesContainer.widthAnchor.constraint(
                equalTo: stickerPagingScrollView.frameLayoutGuide.widthAnchor,
                multiplier: numberOfPages
            ),
        ])

        // Place and set up constraints for sticker pages.
        for (index, collectionView) in stickerPackCollectionViews.enumerated() {
            collectionView.isDirectionalLockEnabled = true
            collectionView.stickerDelegate = self

            // We want the current page on top, to prevent weird
            // animations when we initially calculate our frame.
            if collectionView == currentPageCollectionView {
                stickerPagesContainer.addSubview(collectionView)
            } else {
                stickerPagesContainer.insertSubview(collectionView, at: 0)
            }

            collectionView.translatesAutoresizingMaskIntoConstraints = false
            // Calculate X-position for each page. Make sure to use `left` instead of `leading`.
            let xPositionConstraint = collectionView.leftAnchor.constraint(
                equalTo: stickerPagesContainer.leftAnchor,
                constant: CGFloat(index) * pageWidth
            )
            NSLayoutConstraint.activate([
                // Each page is as wide as the view or `stickerPagingScrollView` is.
                collectionView.widthAnchor.constraint(equalTo: stickerPagingScrollView.frameLayoutGuide.widthAnchor),

                xPositionConstraint,

                // Top and bottom are pinned to `stickerPagesContainer` which has its height
                // fixed to height of `stickerPagingScrollView`.
                collectionView.topAnchor.constraint(equalTo: stickerPagesContainer.topAnchor),
                collectionView.bottomAnchor.constraint(equalTo: stickerPagesContainer.bottomAnchor),
            ])

            stickerPackCollectionViewConstraints.append(xPositionConstraint)
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
        let pageWidth = pageWidth

        // Do nothing if views have not been laid out yet.
        guard pageWidth > 0 else { return }

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

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        checkForPageChange()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        userStartedScrolling()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        userStoppedScrolling(waitingForDeceleration: decelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        userStoppedScrolling()
    }
}

// MARK: StickerPackCollectionViewDelegate

extension StickerPickerPageView: StickerPackCollectionViewDelegate {

    func didSelectSticker(_ stickerInfo: StickerInfo) {
        delegate?.didSelectSticker(stickerInfo)
    }

    func stickerPreviewHostView() -> UIView? {
        return window
    }

    func stickerPreviewHasOverlay() -> Bool {
        return true
    }
}
