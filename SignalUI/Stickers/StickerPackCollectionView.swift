//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol StickerPackCollectionViewDelegate: StickerPickerDelegate, StickerPickerContextMenuDelegate {}

public class StickerPackCollectionView: UICollectionView {
    public struct StickerContextMenuActions: OptionSet {
        public let rawValue: UInt

        public init(rawValue: UInt) {
            self.rawValue = rawValue
        }

        // Sticker actions
        public static let sendSticker = StickerContextMenuActions(rawValue: 1 << 0)
        public static let favorite = StickerContextMenuActions(rawValue: 1 << 1)
        public static let unfavorite = StickerContextMenuActions(rawValue: 1 << 2)
        public static let viewPackFromSticker = StickerContextMenuActions(rawValue: 1 << 3)
        public static let removeFromRecents = StickerContextMenuActions(rawValue: 1 << 4)

        // Section header actions
        public static let sendPack = StickerContextMenuActions(rawValue: 1 << 5)
        public static let viewPackFromHeader = StickerContextMenuActions(rawValue: 1 << 6)
        public static let removePack = StickerContextMenuActions(rawValue: 1 << 7)
        public static let clearRecents = StickerContextMenuActions(rawValue: 1 << 8)

        public static let all: StickerContextMenuActions = [
            .sendSticker,
            .favorite,
            .unfavorite,
            .viewPackFromSticker,
            .removeFromRecents,
            .sendPack,
            .viewPackFromHeader,
            .removePack,
            .clearRecents,
        ]

        public static let allStickerActions: StickerContextMenuActions = [
            .sendSticker,
            .favorite,
            .unfavorite,
            .viewPackFromSticker,
            .removeFromRecents,
        ]
    }

    private typealias StorySticker = EditorSticker.StorySticker

    private var stickerPackDataSource: StickerPackDataSource? {
        didSet {
            stickerPackDataSource?.add(delegate: self)

            reloadStickers()

            // Scroll to the top.
            contentOffset.y = -contentInset.top
        }
    }

    private var stickerInfos = [StickerInfo]()

    public var stickerCount: Int {
        return stickerInfos.count
    }

    public weak var stickerDelegate: StickerPackCollectionViewDelegate?

    private lazy var sizingHeaderView = StickerPackInfoHeaderView()
    private var stickerPackHeaderConfigure: ((StickerPackInfoHeaderView) -> Void)?
    private let stickerPackHeaderReuseIdentifier = "StickerPackCustomHeader"

    public func registerStickerPackHeaderAndSetConfigure(_ configure: @escaping (StickerPackInfoHeaderView) -> Void) {
        stickerPackHeaderConfigure = configure
        register(
            StickerPackInfoHeaderView.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: stickerPackHeaderReuseIdentifier,
        )
        collectionViewLayout.invalidateLayout()
    }

    public func reconfigureCustomHeader() {
        guard let stickerPackHeaderConfigure else { return }

        // Configure the sizing header view so we can get the right measurements.
        stickerPackHeaderConfigure(sizingHeaderView)

        for view in visibleSupplementaryViews(ofKind: UICollectionView.elementKindSectionHeader) {
            if let header = view as? StickerPackInfoHeaderView {
                stickerPackHeaderConfigure(header)
            }
        }
        collectionViewLayout.invalidateLayout()
    }

    private var shouldShowStoryStickers: Bool {
        if case .showWithDelegate = storyStickerConfiguration {
            // Story sticker configuration must be `showWithDelegate`
            // while also being a "Recents" page.
            return stickerPackDataSource is RecentStickerPackDataSource
        }

        return false
    }

    override public var bounds: CGRect {
        didSet {
            // This is necessary in case view width changes but safe areas don't.
            if bounds.width != oldValue.width {
                updateLayout()
            }
        }
    }

    override public var contentInset: UIEdgeInsets {
        didSet {
            // Content insets affect width available for content.
            if contentInset.totalWidth != oldValue.totalWidth {
                updateLayout()
            }
            if let contentUnavailableViewConstraints {
                contentUnavailableViewConstraints.update(with: contentInset)
            }
        }
    }

    override public func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        // Update layout since we use `safeAreaLayoutGuide` to calculate layout attrs.
        updateLayout()
    }

    private let cellReuseIdentifier = "cellReuseIdentifier"
    private let headerReuseIdentifier = StickerPickerHeaderView.reuseIdentifier
    private let placeholderColor: UIColor

    private let storyStickerConfiguration: StoryStickerConfiguration
    private let shouldShowSectionHeaders: Bool

    private let stickerDownloader: StickerDownloader
    private let stickerManager: StickerManager
    private let db: DB

    private let contextMenuActions: StickerContextMenuActions

    public convenience init(
        placeholderColor: UIColor = .ows_gray45,
        storyStickerConfiguration: StoryStickerConfiguration = .hide,
        shouldShowSectionHeaders: Bool,
        contextMenuActions: StickerContextMenuActions,
    ) {
        self.init(
            placeholderColor: placeholderColor,
            storyStickerConfiguration: storyStickerConfiguration,
            shouldShowSectionHeaders: shouldShowSectionHeaders,
            contextMenuActions: contextMenuActions,
            stickerManager: DependenciesBridge.shared.stickerManager,
            stickerDownloader: DependenciesBridge.shared.stickerDownloader,
            db: DependenciesBridge.shared.db,
        )
    }

    public init(
        placeholderColor: UIColor = .ows_gray45,
        storyStickerConfiguration: StoryStickerConfiguration = .hide,
        shouldShowSectionHeaders: Bool,
        contextMenuActions: StickerContextMenuActions,
        stickerManager: StickerManager,
        stickerDownloader: StickerDownloader,
        db: DB,
    ) {
        self.placeholderColor = placeholderColor
        self.storyStickerConfiguration = storyStickerConfiguration
        self.shouldShowSectionHeaders = shouldShowSectionHeaders
        self.contextMenuActions = contextMenuActions
        self.stickerManager = stickerManager
        self.stickerDownloader = stickerDownloader
        self.db = db

        super.init(frame: .zero, collectionViewLayout: StickerPackCollectionView.buildLayout())

        backgroundColor = .clear

        delegate = self
        dataSource = self

        register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        register(StickerPickerHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: headerReuseIdentifier)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(favoriteStickersDidChange),
            name: StickerManager.favoriteStickersDidChange,
            object: nil,
        )
    }

    public required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Modes

    public func showInstalledPack(stickerPack: StickerPackRecord) {
        stickerPackDataSource = InstalledStickerPackDataSource(
            stickerPackInfo: stickerPack.info,
            stickerManager: stickerManager,
            db: db,
        )
    }

    public func showUninstalledPack(stickerPack: StickerPackRecord) {
        stickerPackDataSource = TransientStickerPackDataSource(
            stickerPackInfo: stickerPack.info,
            shouldDownloadAllStickers: true,
            stickerDownloader: stickerDownloader,
            stickerManager: stickerManager,
            db: db,
        )
    }

    public func showRecents() {
        stickerPackDataSource = RecentStickerPackDataSource(
            stickerManager: stickerManager,
            db: db,
        )
    }

    public func showFavorites() {
        stickerPackDataSource = FavoritesStickerPackDataSource(
            stickerManager: stickerManager,
            db: db,
        )
    }

    public func showSelectedStickerPickerPage(stickerPickerPage: StickerPickerPage) {
        switch (stickerPickerPage) {
        case .favorites:
            showFavorites()
        case .recents:
            showRecents()
        case .pack(let stickerPack):
            showInstalledPack(stickerPack: stickerPack)
        }
    }

    public func show(dataSource: StickerPackDataSource) {
        stickerPackDataSource = dataSource
    }

    // MARK: - Bouncing sticker animation

    // Store bouncingStickerInfo for the duration of the animation
    // to prevent races between adding the animation to a cell and reloading
    // cells, both of which happen quickly when favoriting a sticker.
    private var bouncingStickerInfo: StickerInfo?

    private static let bounceDuration: TimeInterval = 1.5

    public func bounceSticker(_ stickerInfo: StickerInfo) {
        guard !UIAccessibility.isReduceMotionEnabled else {
            return
        }

        guard let index = stickerInfos.firstIndex(of: stickerInfo) else {
            return
        }
        let indexPath = IndexPath(item: index, section: shouldShowStoryStickers ? 1 : 0)

        // Layout before the scroll to make sure we scroll to the right place,
        // and after to make sure the cell we scrolled to exists.
        layoutIfNeeded()
        scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        layoutIfNeeded()

        bouncingStickerInfo = stickerInfo
        if let cell = cellForItem(at: indexPath) {
            addBounceAnimation(to: cell)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bounceDuration) { [weak self] in
            self?.bouncingStickerInfo = nil
        }
    }

    private func addBounceAnimation(to cell: UICollectionViewCell) {
        let hopHeights: [CGFloat] = [14, 10, 6, 3]
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
        animation.values = [0] + hopHeights.flatMap { [-$0, 0] }
        animation.timingFunctions = hopHeights.flatMap { _ in
            [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        }
        animation.duration = Self.bounceDuration
        cell.contentView.layer.add(animation, forKey: "bounceSticker")
    }

    // MARK: Empty Content view

    private struct EdgeConstraints {
        let top: NSLayoutConstraint
        let leading: NSLayoutConstraint
        let bottom: NSLayoutConstraint
        let trailing: NSLayoutConstraint

        var constraints: [NSLayoutConstraint] {
            [top, leading, bottom, trailing]
        }

        func update(with insets: UIEdgeInsets) {
            top.constant = insets.top
            leading.constant = insets.leading
            bottom.constant = -insets.bottom
            trailing.constant = -insets.trailing
        }
    }

    private var contentUnavailableView: UIView?

    private var contentUnavailableViewConstraints: EdgeConstraints?

    private func createContentUnavailableView() -> UIView {
        let view = UIView()
        view.directionalLayoutMargins = .init(margin: 20)
        let titleLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
            "STICKER_CATEGORY_RECENTS_EMPTY_TITLE",
            comment: "Title of the helper text displayed when Recent stickers are empty.",
        ))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = .dynamicTypeHeadline // slightly larger than subtitle
        let subtitleLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
            "STICKER_CATEGORY_RECENTS_EMPTY_SUBTITLE",
            comment: "Subtitle of the helper text displayed when Recent stickers are empty.",
        ))
        subtitleLabel.adjustsFontForContentSizeCategory = true
        let vStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        vStack.axis = .vertical
        vStack.spacing = 2
        vStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(vStack)
        NSLayoutConstraint.activate([
            vStack.topAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.topAnchor),
            vStack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            vStack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            vStack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        return view
    }

    private func updateEmptyState() {
        let isEmpty = stickerInfos.isEmpty

        // "Content Unavailable" view is created on demand here.
        if isEmpty, contentUnavailableView == nil {
            let view = createContentUnavailableView()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            let constraints = EdgeConstraints(
                top: view.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
                leading: view.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
                bottom: view.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
                trailing: view.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            )
            constraints.update(with: contentInset)
            NSLayoutConstraint.activate(constraints.constraints)

            contentUnavailableView = view
            contentUnavailableViewConstraints = constraints
        }

        if isEmpty, let contentUnavailableView {
            bringSubviewToFront(contentUnavailableView)
            contentUnavailableView.isHidden = false
        } else {
            contentUnavailableView?.isHidden = true
        }
    }

    // MARK: Events

    private func reloadStickers() {
        AssertIsOnMainThread()

        defer { reloadData() }

        guard let stickerPackDataSource else {
            stickerInfos = []
            return
        }

        let installedStickerInfos = stickerPackDataSource.installedStickerInfos

        if stickerPackDataSource is TransientStickerPackDataSource {
            guard let allStickerInfos = stickerPackDataSource.getStickerPack()?.stickerInfos() else {
                stickerInfos = []
                owsAssertDebug(installedStickerInfos.isEmpty)
                return
            }

            stickerInfos = allStickerInfos
            owsAssertDebug(stickerInfos.count >= installedStickerInfos.count)
        } else {
            stickerInfos = installedStickerInfos
        }
    }

    override public func reloadData() {
        super.reloadData()

        updateEmptyState()
    }

    @objc
    private func favoriteStickersDidChange() {
        // Rebuild the cells' accessibility custom actions so the
        // favorite/unfavorite action reflects the current state.
        reconfigureItems(at: indexPathsForVisibleItems)
    }

    private func imageView(forStickerInfo stickerInfo: StickerInfo) -> UIView? {
        guard let stickerPackDataSource else {
            owsFailDebug("Missing stickerPackDataSource.")
            return nil
        }
        return StickerView.stickerView(forStickerInfo: stickerInfo, dataSource: stickerPackDataSource)
    }

    private let reusableStickerViewCache = StickerViewCache(maxSize: 32)

    private func reusableStickerView(forStickerInfo stickerInfo: StickerInfo) -> StickerReusableView {
        let view: StickerReusableView = {
            if let view = reusableStickerViewCache.object(forKey: stickerInfo) { return view }
            let view = StickerReusableView()
            reusableStickerViewCache.setObject(view, forKey: stickerInfo)
            return view
        }()

        guard !view.hasStickerView else { return view }

        guard let imageView = imageView(forStickerInfo: stickerInfo) else {
            view.showPlaceholder(color: placeholderColor)
            return view
        }

        view.configure(with: imageView)

        return view
    }

    // MARK: Context Menu Blur

    private var contextMenuBlurView: UIVisualEffectView?

    private func showContextMenuBlur() {
        guard contextMenuBlurView == nil, let window else { return }

        let blurView = UIVisualEffectView(effect: nil)
        blurView.frame = window.bounds
        blurView.isUserInteractionEnabled = false
        blurView.effect = UIBlurEffect(style: .regular)
        window.addSubview(blurView)

        contextMenuBlurView = blurView
    }

    private func hideContextMenuBlur() {
        guard contextMenuBlurView != nil else {
            return
        }
        let blurView = contextMenuBlurView
        contextMenuBlurView = nil

        blurView?.effect = nil
        blurView?.removeFromSuperview()
    }
}

// MARK: - UICollectionViewDelegate

extension StickerPackCollectionView: UICollectionViewDelegate {

    private func isStoryStickerSection(sectionIndex: Int) -> Bool {
        return shouldShowStoryStickers && sectionIndex == 0
    }

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.debug("")

        if isStoryStickerSection(sectionIndex: indexPath.section) {
            guard let storySticker = StorySticker.pickerStickers[safe: indexPath.item] else {
                owsFailDebug("Invalid index path: \(indexPath)")
                return
            }
            guard case .showWithDelegate(let storyStickerPickerDelegate) = storyStickerConfiguration else {
                owsFailDebug("Unexpectedly found hidden story stickers.")
                return
            }

            storyStickerPickerDelegate.didSelect(storySticker: storySticker)
            return
        }

        guard
            let stickerInfo = stickerInfos[safe: indexPath.row],
            let stickerMetadata = stickerPackDataSource?.metadata(forSticker: stickerInfo)
        else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }
        self.stickerDelegate?.didSelectSticker(stickerMetadata)
    }
}

// MARK: - UICollectionViewDataSource

extension StickerPackCollectionView: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return shouldShowStoryStickers ? 2 : 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        if isStoryStickerSection(sectionIndex: sectionIdx) {
            return StorySticker.pickerStickers.count
        }
        return stickerInfos.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath)
        cell.contentView.removeAllSubviews()

        if isStoryStickerSection(sectionIndex: indexPath.section) {
            guard let storySticker = StorySticker.pickerStickers[safe: indexPath.row] else {
                owsFailDebug("Invalid index path: \(indexPath)")
                return cell
            }
            let stickerView = storySticker.previewView()
            cell.contentView.addSubview(stickerView)
            stickerView.autoPinEdgesToSuperviewEdges()
            cell.isAccessibilityElement = true
            cell.accessibilityTraits = .button
            cell.accessibilityLabel = storySticker.accessibilityLabel()
            cell.accessibilityHint = OWSLocalizedString(
                "ACCESSIBILITY_HINT_STICKER",
                comment: "AX hint letting a user know this button sends a sticker",
            )
            cell.accessibilityCustomActions = nil
            return cell
        }

        guard let stickerInfo = stickerInfos[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return cell
        }

        // If bouncingStickerInfo is not nil, it means we started a bounce animation for this
        // stickerInfo but may have reloaded the cell since then. Add the animation back to make
        // sure it's user-visible.
        if stickerInfo == bouncingStickerInfo {
            addBounceAnimation(to: cell)
        }

        let cellView = reusableStickerView(forStickerInfo: stickerInfo)
        cell.contentView.addSubview(cellView)
        cellView.autoPinEdgesToSuperviewEdges()

        cell.isAccessibilityElement = true
        cell.accessibilityTraits = .button
        cell.accessibilityLabel = stickerAccessibilityLabel(for: stickerInfo)
        cell.accessibilityHint = OWSLocalizedString("ACCESSIBILITY_HINT_STICKER", comment: "AX hint letting a user know this button sends a sticker")
        cell.accessibilityCustomActions = stickerActions(stickerInfo: stickerInfo).map(\.accessibilityAction)

        if !cell.interactions.contains(where: { $0 is UIContextMenuInteraction }) {
            cell.addInteraction(UIContextMenuInteraction(delegate: self))
        }

        return cell
    }

    private func stickerAccessibilityLabel(for stickerInfo: StickerInfo) -> String {
        if let stickerMetadata = stickerPackDataSource?.metadata(forSticker: stickerInfo) {
            return stickerMetadata.localizedAccessibilityLabel
        }
        return OWSLocalizedString("ACCESSIBILITY_LABEL_STICKER", comment: "Accessibility label for stickers.")
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath,
    ) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }

        if
            let stickerPackHeaderConfigure,
            let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: stickerPackHeaderReuseIdentifier,
                for: indexPath,
            ) as? StickerPackInfoHeaderView
        {
            guard indexPath.section == 0 else {
                owsFailDebug("Only first section should have sticker pack header")
                return UICollectionReusableView()
            }
            stickerPackHeaderConfigure(header)
            return header
        }

        let headerView = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: headerReuseIdentifier,
            for: indexPath,
        )

        if let headerView = headerView as? StickerPickerHeaderView {
            let axMenuItems = headerMenuActions().map(\.accessibilityAction)
            headerView.configure(text: self.headerText(for: indexPath.section), menu: self.headerMenu(), accessibilityActions: axMenuItems)
        }

        return headerView
    }

    private func headerText(for section: Int) -> String? {
        if shouldShowStoryStickers {
            if section == 0 {
                return OWSLocalizedString(
                    "STICKER_CATEGORY_FEATURED_NAME",
                    comment: "The name for the sticker category 'Featured'",
                )
            } else {
                return OWSLocalizedString(
                    "STICKER_CATEGORY_RECENTS_NAME",
                    comment: "The name for the sticker category 'Recents'",
                )
            }
        } else if shouldShowSectionHeaders {
            switch stickerPackDataSource {
            case nil:
                // Expected in the "no installed packs" case, we show an empty view.
                return nil
            case is FavoritesStickerPackDataSource:
                return OWSLocalizedString(
                    "STICKER_KEYBOARD_SECTION_HEADER_LABEL_FAVORITES",
                    comment: "Section header for favorites in the sticker keyboard",
                )
            case is RecentStickerPackDataSource:
                return OWSLocalizedString(
                    "STICKER_KEYBOARD_SECTION_HEADER_LABEL_RECENTS",
                    comment: "Section header for recents in the sticker keyboard",
                )
            case is TransientStickerPackDataSource, is InstalledStickerPackDataSource:
                return stickerPackDataSource?.title
            default:
                owsFailDebug("Unexpected data source: \(type(of: stickerPackDataSource))")
                return nil
            }
        }
        return nil
    }
}

extension StickerPackCollectionView: UICollectionViewDelegateFlowLayout {

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int,
    ) -> CGSize {
        if stickerPackHeaderConfigure != nil {
            let availableWidth = collectionView.safeAreaLayoutGuide.layoutFrame.size.width - collectionView.contentInset.totalWidth
            let targetSize = CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
            return sizingHeaderView.sizeThatFits(targetSize)
        }

        guard let headerText = headerText(for: section) else { return .zero }

        let headerView = StickerPickerHeaderView()
        headerView.label.text = headerText
        return headerView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

private class StickerPickerHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "StickerPickerHeaderView"

    let label = UILabel()

    /// Transparent button over the label that shows the header's menu on long press.
    private let menuButton = UIButton(type: .custom)

    override init(frame: CGRect) {
        super.init(frame: frame)

        directionalLayoutMargins = NSDirectionalEdgeInsets(hMargin: 0, vMargin: 12)
        insetsLayoutMarginsFromSafeArea = false
        label.font = UIFont.dynamicTypeSubheadline.semibold()
        label.textColor = .Signal.label
        addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        label.setCompressionResistanceHigh()

        menuButton.showsMenuAsPrimaryAction = false
        menuButton.accessibilityTraits = .header
        addSubview(menuButton)
        menuButton.autoPinEdges(toEdgesOf: label)
        isAccessibilityElement = true
        accessibilityTraits = .header
    }

    override var accessibilityLabel: String? {
        get { label.text }
        set { super.accessibilityLabel = newValue }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String?, menu: UIMenu?, accessibilityActions: [UIAccessibilityCustomAction]?) {
        label.text = text
        menuButton.menu = menu
        menuButton.isHidden = menu == nil
        menuButton.accessibilityLabel = text
        label.isAccessibilityElement = menu == nil
        accessibilityCustomActions = accessibilityActions
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        var labelSize = label.sizeThatFits(size)
        labelSize.width += layoutMargins.left + layoutMargins.right
        labelSize.height += layoutMargins.top + layoutMargins.bottom
        return labelSize
    }
}

// MARK: - Layout

extension StickerPackCollectionView {

    private static let minimumCellSpacing: CGFloat = 8

    private class func buildLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = minimumCellSpacing
        layout.minimumLineSpacing = minimumCellSpacing
        return layout
    }

    func updateLayout() {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            // The layout isn't set while the view is being initialized.
            return
        }

        let contentWidth = safeAreaLayoutGuide.layoutFrame.size.width - contentInset.totalWidth
        let cellSpacing = Self.minimumCellSpacing
        let preferredCellSize: CGFloat = 80
        let columnCount = UInt((contentWidth + cellSpacing) / (preferredCellSize + cellSpacing))
        let cellWidth = (contentWidth - cellSpacing * (CGFloat(columnCount) - 1)) / CGFloat(columnCount)
        let itemSize = CGSize(square: cellWidth)

        if itemSize != flowLayout.itemSize {
            flowLayout.itemSize = itemSize
            flowLayout.invalidateLayout()
        }
    }
}

extension StickerPackCollectionView: StickerPackDataSourceDelegate {

    public func stickerPackDataDidChange() {
        reloadStickers()
    }
}

// MARK: - Context Menu Support

extension StickerPackCollectionView: UIContextMenuInteractionDelegate {

    /// A struct to generalize StickerMenuActions so they can be shared between
    /// the context menu and custom accessibility menu items.
    private struct StickerMenuAction {
        let type: StickerContextMenuActions
        let title: String
        let image: UIImage?
        var attributes: UIMenuElement.Attributes = []
        let handler: () -> Void

        var menuAction: UIAction {
            UIAction(title: title, image: image, attributes: attributes) { _ in handler() }
        }

        var accessibilityAction: UIAccessibilityCustomAction {
            UIAccessibilityCustomAction(name: title, image: image) { _ in
                handler()
                return true
            }
        }
    }

    private func headerMenuActions() -> [StickerMenuAction] {
        switch stickerPackDataSource {
        case nil:
            // Expected in the "no installed packs" case, we show an empty view.
            return []
        case is FavoritesStickerPackDataSource:
            return []
        case is RecentStickerPackDataSource:
            let actions = [StickerMenuAction(
                type: .clearRecents,
                title: OWSLocalizedString(
                    "STICKER_KEYBOARD_BUTTON_CLEAR_RECENTS",
                    comment: "Label for the button to clear all sticker recents",
                ),
                image: UIImage(named: "trash"),
                attributes: .destructive,
            ) { [weak self] in
                let confirmClearRecentsSheet = ActionSheetController(
                    message: OWSLocalizedString(
                        "STICKER_PACK_CONFIRM_CLEAR_RECENTS_MESSAGE",
                        comment: "Message for a sheet asking the user to confirm they want to clear recently used stickers",
                    ),
                )

                confirmClearRecentsSheet.addAction(
                    ActionSheetAction(
                        title: OWSLocalizedString(
                            "STICKER_PACK_CLEAR_RECENTS_BUTTON",
                            comment: "Button to confirm a user wants to clear recent stickers",
                        ),
                        style: .destructive,
                        handler: { [weak self] _ in
                            self?.db.write { tx in
                                self?.stickerManager.removeAllRecentStickers(transaction: tx)
                            }
                        },
                    ),
                )
                confirmClearRecentsSheet.addAction(.cancel)
                OWSActionSheets.showActionSheet(confirmClearRecentsSheet)
            }]
            return actions.filter { contextMenuActions.contains($0.type) }
        case is TransientStickerPackDataSource, is InstalledStickerPackDataSource:
            let actions = [
                StickerMenuAction(
                    type: .sendPack,
                    title: OWSLocalizedString("SEND_BUTTON_TITLE", comment: "Label for the button to send a message"),
                    image: UIImage(named: "arrow-circle-up"),
                ) { [weak self] in
                    if let stickerPackInfo = self?.stickerPackDataSource?.info {
                        self?.stickerDelegate?.queueStickerPackForSending(stickerPackInfo)
                    }
                },
                StickerMenuAction(
                    type: .viewPackFromHeader,
                    title: OWSLocalizedString(
                        "STICKER_BUTTON_VIEW_PACK",
                        comment: "Title for a button to view a sticker pack",
                    ),
                    image: UIImage(named: "stickerpack"),
                ) { [weak self] in
                    if let stickerPackInfo = self?.stickerPackDataSource?.info {
                        self?.stickerDelegate?.viewStickerPack(stickerPackInfo)
                    }
                },
                StickerMenuAction(
                    type: .removePack,
                    title: OWSLocalizedString(
                        "STICKER_REMOVE_PACK_BUTTON",
                        comment: "Title for a button to remove a sticker pack",
                    ),
                    image: UIImage(named: "minus-circle"),
                ) { [weak self] in
                    let confirmUninstallSheet = ActionSheetController(
                        title: OWSLocalizedString(
                            "STICKER_PACK_CONFIRM_REMOVE_TITLE",
                            comment: "Title for a sheet asking the user to confirm they want to remove a sticker pack",
                        ),
                        message: OWSLocalizedString(
                            "STICKER_PACK_CONFIRM_REMOVE_MESSAGE",
                            comment: "Message for a sheet asking the user to confirm they want to remove a sticker pack",
                        ),
                    )

                    confirmUninstallSheet.addAction(
                        ActionSheetAction(
                            title: OWSLocalizedString(
                                "STICKER_PACK_CONFIRM_REMOVE_BUTTON",
                                comment: "Button to confirm a user wants to remove a sticker pack",
                            ),
                            style: .destructive,
                            handler: { [weak self] _ in
                                if let stickerPackInfo = self?.stickerPackDataSource?.info {
                                    self?.db.write { tx in
                                        self?.stickerManager.uninstallStickerPack(stickerPackInfo: stickerPackInfo, wasLocallyInitiated: true, transaction: tx)
                                    }
                                }
                            },
                        ),
                    )
                    confirmUninstallSheet.addAction(.cancel)
                    OWSActionSheets.showActionSheet(confirmUninstallSheet)
                },
            ]
            return actions.filter { contextMenuActions.contains($0.type) }
        default:
            owsFailDebug("Unexpected data source: \(type(of: stickerPackDataSource))")
            return []
        }
    }

    private func headerMenu() -> UIMenu? {
        let actions = headerMenuActions()
        if actions.isEmpty {
            return nil
        }
        return UIMenu(children: actions.map(\.menuAction))
    }

    private func getFavoriteActionForSticker(stickerInfo: StickerInfo) -> StickerMenuAction {
        let isStickerFavorited = db.read { tx in stickerManager.isStickerFavorited(stickerInfo: stickerInfo, tx: tx) }

        if !isStickerFavorited {
            return StickerMenuAction(
                type: .favorite,
                title: OWSLocalizedString(
                    "STICKER_BUTTON_ADD_FAVORITES",
                    comment: "Label for button to add sticker to favorites",
                ),
                image: UIImage(named: "favorite"),
            ) { [weak self] in
                guard
                    let stickerMetadata = self?.stickerPackDataSource?.metadata(forSticker: stickerInfo)
                else {
                    owsFailDebug("invalid sticker on long press")
                    return
                }
                Task {
                    do {
                        try await self?.stickerManager.addStickerToFavorites(stickerMetadata: stickerMetadata)
                    } catch StickerFavoriteError.limitReached {
                        self?.stickerDelegate?.stickerFavoriteDidChange(stickerInfo, change: .limitReached)
                        return
                    } catch {
                        owsFailDebug("Failed to add sticker to favorites: \(error)")
                        return
                    }
                    self?.stickerDelegate?.stickerFavoriteDidChange(stickerInfo, change: .added)
                }
            }
        }

        return StickerMenuAction(
            type: .unfavorite,
            title: OWSLocalizedString(
                "STICKER_BUTTON_REMOVE_FAVORITES",
                comment: "Label for button to remove sticker from favorites",
            ),
            image: UIImage(named: "favorite-slash"),
        ) { [weak self] in
            Task {
                guard let self else { return }
                await self.stickerManager.removeStickerFromFavorites(stickerInfo: stickerInfo)
                self.stickerDelegate?.stickerFavoriteDidChange(stickerInfo, change: .removed)
            }
        }
    }

    private func stickerActions(stickerInfo: StickerInfo) -> [StickerMenuAction] {
        var actions: [StickerMenuAction] = []
        actions.append(
            StickerMenuAction(
                type: .sendSticker,
                title: OWSLocalizedString("SEND_STICKER_BUTTON_TITLE", comment: "Label for the button to send a sticker message"),
                image: UIImage(named: "arrow-circle-up"),
            ) { [weak self] in
                guard
                    let stickerMetadata = self?.stickerPackDataSource?.metadata(forSticker: stickerInfo)
                else {
                    owsFailDebug("invalid sticker on long press")
                    return
                }
                self?.stickerDelegate?.sendSticker(stickerMetadata)
            },
        )

        if BuildFlags.stickerFavorites {
            let stickerFavoriteAction = self.getFavoriteActionForSticker(stickerInfo: stickerInfo)
            actions.append(stickerFavoriteAction)
        }

        actions.append(
            contentsOf: [
                StickerMenuAction(
                    type: .viewPackFromSticker,
                    title: OWSLocalizedString(
                        "STICKER_BUTTON_VIEW_PACK",
                        comment: "Title for a button to view a sticker pack",
                    ),
                    image: UIImage(named: "stickerpack"),
                ) { [weak self] in
                    let stickerPackInfo = StickerPackInfo(packId: stickerInfo.packId, packKey: stickerInfo.packKey)
                    self?.stickerDelegate?.viewStickerPack(stickerPackInfo)
                },
            ],
        )

        if self.stickerPackDataSource is RecentStickerPackDataSource {
            actions.append(
                contentsOf: [
                    StickerMenuAction(
                        type: .removeFromRecents,
                        title: OWSLocalizedString(
                            "STICKER_BUTTON_REMOVE_FROM_RECENTS",
                            comment: "Title for a button to remove a sticker from recents",
                        ),
                        image: UIImage(named: "trash"),
                        attributes: .destructive,
                    ) { [weak self] in
                        self?.db.write { tx in
                            self?.stickerManager.removeFromRecentStickers(stickerInfo, transaction: tx)
                        }
                    },
                ],
            )
        }
        return actions.filter { contextMenuActions.contains($0.type) }
    }

    private func contextMenuConfigForSticker(stickerInfo: StickerInfo) -> UIContextMenuConfiguration? {
        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: nil,
            actionProvider: { [weak self] _ in
                guard let self else { return UIMenu(children: []) }

                let stickerActions = stickerActions(stickerInfo: stickerInfo)
                return UIMenu(children: stickerActions.map(\.menuAction))
            },
        )
    }

    public func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        if
            let cell = interaction.view as? UICollectionViewCell,
            let indexPath = indexPath(for: cell),
            !isStoryStickerSection(sectionIndex: indexPath.section),
            let stickerInfo = stickerInfos[safe: indexPath.row]
        {
            return contextMenuConfigForSticker(stickerInfo: stickerInfo)
        }

        return nil
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?,
    ) {
        showContextMenuBlur()
    }

    public func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?,
    ) {
        hideContextMenuBlur()
    }
}
