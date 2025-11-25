//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

public protocol StickerPackCollectionViewDelegate: StickerPickerDelegate {
    func stickerPreviewHostView() -> UIView?
    func stickerPreviewHasOverlay() -> Bool
}

public class StickerPackCollectionView: UICollectionView {

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

    public init(
        placeholderColor: UIColor = .ows_gray45,
        storyStickerConfiguration: StoryStickerConfiguration = .hide
    ) {
        self.placeholderColor = placeholderColor
        self.storyStickerConfiguration = storyStickerConfiguration

        super.init(frame: .zero, collectionViewLayout: StickerPackCollectionView.buildLayout())

        backgroundColor = .clear

        delegate = self
        dataSource = self

        register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        register(StickerPickerHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: headerReuseIdentifier)

        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress)))
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Modes

    public func showInstalledPack(stickerPack: StickerPack) {
        stickerPackDataSource = InstalledStickerPackDataSource(stickerPackInfo: stickerPack.info)
    }

    public func showUninstalledPack(stickerPack: StickerPack) {
        stickerPackDataSource = TransientStickerPackDataSource(stickerPackInfo: stickerPack.info,
                                                               shouldDownloadAllStickers: true)
    }

    public func showRecents() {
        stickerPackDataSource = RecentStickerPackDataSource()
    }

    public func showInstalledPackOrRecents(stickerPack: StickerPack?) {
        if let stickerPack {
            showInstalledPack(stickerPack: stickerPack)
        } else {
            showRecents()
        }
    }

    public func show(dataSource: StickerPackDataSource) {
        stickerPackDataSource = dataSource
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
            comment: "Title of the helper text displayed when Recent stickers are empty."
        ))
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.font = .dynamicTypeHeadline // slightly larger than subtitle
        let subtitleLabel = UILabel.explanationTextLabel(text: OWSLocalizedString(
            "STICKER_CATEGORY_RECENTS_EMPTY_SUBTITLE",
            comment: "Subtitle of the helper text displayed when Recent stickers are empty."
        ))
        subtitleLabel.adjustsFontForContentSizeCategory = true
        let vStack = UIStackView(arrangedSubviews: [ titleLabel, subtitleLabel ])
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
            let view  = createContentUnavailableView()
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            let constraints = EdgeConstraints(
                top: view.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
                leading: view.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
                bottom: view.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
                trailing: view.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor)
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
            guard let allStickerInfos = stickerPackDataSource.getStickerPack()?.stickerInfos else {
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

    public override func reloadData() {
        super.reloadData()

        updateEmptyState()
    }

    // MARK: Sticker Preview

    @objc
    private func handleLongPress(sender: UIGestureRecognizer) {
        switch sender.state {
        case .began, .changed:
            break
        case .possible, .ended, .cancelled, .failed:
            fallthrough
        @unknown default:
            hidePreview()
            return
        }

        // Do nothing if we're not currently pressing on a pack, we'll hide it when we release
        // or update it when the user moves their touch over another pack. This prevents "flashing"
        // as the user moves their finger between packs.
        guard let indexPath = self.indexPathForItem(at: sender.location(in: self)),
              !isStoryStickerSection(sectionIndex: indexPath.section) else { return }
        guard let stickerInfo = stickerInfos[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }

        ensurePreview(stickerInfo: stickerInfo)
    }

    private var previewView: UIView?

    private var previewStickerInfo: StickerInfo?

    private func hidePreview() {
        previewView?.removeFromSuperview()
        previewView = nil
        previewStickerInfo = nil
    }

    private func ensurePreview(stickerInfo: StickerInfo) {
        if previewView != nil, let previewStickerInfo, previewStickerInfo == stickerInfo {
            // Already showing a preview for this sticker.
            return
        }

        hidePreview()

        guard let stickerView = imageView(forStickerInfo: stickerInfo) else {
            Logger.warn("Couldn't load sticker for display")
            return
        }
        guard let stickerDelegate else {
            owsFailDebug("Missing stickerDelegate")
            return
        }
        guard let hostView = stickerDelegate.stickerPreviewHostView() else {
            owsFailDebug("Missing host view.")
            return
        }

        if stickerDelegate.stickerPreviewHasOverlay() {
            let overlayView = UIView()
            overlayView.backgroundColor = Theme.backgroundColor.withAlphaComponent(0.5)
            hostView.addSubview(overlayView)
            overlayView.autoPinEdgesToSuperviewEdges()
            overlayView.setContentHuggingLow()
            overlayView.setCompressionResistanceLow()
            overlayView.addSubview(stickerView)
            previewView = overlayView
        } else {
            hostView.addSubview(stickerView)
            previewView = stickerView
        }

        previewStickerInfo = stickerInfo

        stickerView.autoPinToSquareAspectRatio()
        stickerView.autoCenterInSuperview()
        let vMargin: CGFloat = 40
        let hMargin: CGFloat = 60
        stickerView.autoSetDimension(.width, toSize: hostView.height - vMargin * 2, relation: .lessThanOrEqual)
        stickerView.autoPinEdge(toSuperviewEdge: .top, withInset: vMargin, relation: .greaterThanOrEqual)
        stickerView.autoPinEdge(toSuperviewEdge: .bottom, withInset: vMargin, relation: .greaterThanOrEqual)
        stickerView.autoPinEdge(toSuperviewEdge: .leading, withInset: hMargin, relation: .greaterThanOrEqual)
        stickerView.autoPinEdge(toSuperviewEdge: .trailing, withInset: hMargin, relation: .greaterThanOrEqual)
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

        guard let stickerInfo = stickerInfos[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }

        self.stickerDelegate?.didSelectSticker(stickerInfo)
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
            return cell
        }

        guard let stickerInfo = stickerInfos[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return cell
        }

        let cellView = reusableStickerView(forStickerInfo: stickerInfo)
        cell.contentView.addSubview(cellView)
        cellView.autoPinEdgesToSuperviewEdges()

        return cell
    }

    public func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: headerReuseIdentifier, for: indexPath)

        guard
            kind == UICollectionView.elementKindSectionHeader,
            let headerLabel = headerView as? StickerPickerHeaderView
        else {
            return headerView
        }

        headerLabel.label.text = self.headerText(for: indexPath.section)

        return headerLabel
    }

    private func headerText(for section: Int) -> String? {
        guard shouldShowStoryStickers else { return nil }
        if section == 0 {
            return OWSLocalizedString(
                "STICKER_CATEGORY_FEATURED_NAME",
                comment: "The name for the sticker category 'Featured'"
            )
        } else {
            return OWSLocalizedString(
                "STICKER_CATEGORY_RECENTS_NAME",
                comment: "The name for the sticker category 'Recents'"
            )
        }
    }
}

extension StickerPackCollectionView: UICollectionViewDelegateFlowLayout {

    public func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int
    ) -> CGSize {
        guard let headerText = headerText(for: section) else { return .zero }

        let headerView = StickerPickerHeaderView()
        headerView.label.text = headerText
        return headerView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}

private class StickerPickerHeaderView: UICollectionReusableView {

    static let reuseIdentifier = "StickerPickerHeaderView"

    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 0)

        label.font = UIFont.dynamicTypeFootnoteClamped.semibold()
        label.textColor = Theme.darkThemeSecondaryTextAndIconColor
        addSubview(label)
        label.autoPinEdgesToSuperviewMargins()
        label.setCompressionResistanceHigh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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

// MARK: -

extension StickerPackCollectionView: StickerPackDataSourceDelegate {

    public func stickerPackDataDidChange() {
        reloadStickers()
    }
}
