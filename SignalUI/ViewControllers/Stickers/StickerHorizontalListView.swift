//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public protocol StickerHorizontalListViewItem {
    var view: UIView { get }
    var didSelectBlock: () -> Void { get }
    var isSelected: Bool { get }
    var accessibilityName: String { get }
}

// MARK: -

public class StickerHorizontalListViewItemSticker: StickerHorizontalListViewItem {
    private let stickerInfo: StickerInfo
    public let didSelectBlock: () -> Void
    public let isSelectedBlock: () -> Bool
    private weak var cache: StickerViewCache?

    // This initializer can be used for cells which are never selected.
    public convenience init(stickerInfo: StickerInfo,
                            didSelectBlock: @escaping () -> Void,
                            cache: StickerViewCache? = nil) {
        self.init(stickerInfo: stickerInfo, didSelectBlock: didSelectBlock, isSelectedBlock: { false }, cache: cache)
    }

    public init(stickerInfo: StickerInfo,
                didSelectBlock: @escaping () -> Void,
                isSelectedBlock: @escaping () -> Bool,
                cache: StickerViewCache? = nil) {
        self.stickerInfo = stickerInfo
        self.didSelectBlock = didSelectBlock
        self.isSelectedBlock = isSelectedBlock
        self.cache = cache
    }

    private func reusableStickerView(forStickerInfo stickerInfo: StickerInfo) -> StickerReusableView {
        let view: StickerReusableView = {
            if let view = cache?.object(forKey: stickerInfo) { return view }
            let view = StickerReusableView()
            cache?.setObject(view, forKey: stickerInfo)
            return view
        }()

        guard !view.hasStickerView else { return view }

        guard let stickerView = StickerView.stickerView(forInstalledStickerInfo: stickerInfo) else {
            view.showPlaceholder()
            return view
        }

        stickerView.layer.minificationFilter = .trilinear
        view.configure(with: stickerView)

        return view
    }

    public var view: UIView { reusableStickerView(forStickerInfo: stickerInfo) }

    public var isSelected: Bool {
        return isSelectedBlock()
    }

    public var accessibilityName: String {
        // We just need a stable identifier.
        return "pack." + stickerInfo.asKey()
    }
}

// MARK: -

public class StickerHorizontalListViewItemRecents: StickerHorizontalListViewItem {

    public let didSelectBlock: () -> Void
    public let isSelectedBlock: () -> Bool

    public init(didSelectBlock: @escaping () -> Void, isSelectedBlock: @escaping () -> Bool) {
        self.didSelectBlock = didSelectBlock
        self.isSelectedBlock = isSelectedBlock
    }

    public var view: UIView {
        let imageView = UIImageView()
        imageView.setTemplateImageName("recent-outline-24", tintColor: Theme.secondaryTextAndIconColor)
        return imageView
    }

    public var isSelected: Bool {
        return isSelectedBlock()
    }

    public var accessibilityName: String {
        return "recents"
    }
}

// MARK: -

public class StickerHorizontalListView: UICollectionView {

    private let cellSize: CGFloat
    private let cellInset: CGFloat

    public typealias Item = StickerHorizontalListViewItem

    public var items = [Item]() {
        didSet {
            AssertIsOnMainThread()

            collectionViewLayout.invalidateLayout()
            reloadData()
        }
    }

    private let cellReuseIdentifier = "cellReuseIdentifier"

    public required init(cellSize: CGFloat, cellInset: CGFloat, spacing: CGFloat) {
        self.cellSize = cellSize
        self.cellInset = cellInset
        let layout = LinearHorizontalLayout(itemSize: CGSize(square: cellSize), spacing: spacing)

        super.init(frame: .zero, collectionViewLayout: layout)

        showsHorizontalScrollIndicator = false
        delegate = self
        dataSource = self
        register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)

        setContentHuggingHorizontalLow()
        setCompressionResistanceHorizontalLow()
    }

    // Reload visible items to refresh the "selected" state
    func updateSelections(scrollToSelectedItem: Bool = false) {
        reloadData()
        guard scrollToSelectedItem else { return }
        guard let (selectedIndex, _) = items.enumerated().first(where: { $1.isSelected }) else { return }
        scrollToItem(at: IndexPath(row: selectedIndex, section: 0), at: .centeredHorizontally, animated: true)
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - UICollectionViewDelegate

extension StickerHorizontalListView: UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.debug("")

        guard let item = items[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }

        item.didSelectBlock()

        // Selection has changed; update cells to reflect that.
        self.reloadData()
    }
}

// MARK: - UICollectionViewDataSource

extension StickerHorizontalListView: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        return items.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // We could eventually use cells that lazy-load the sticker views
        // when the cells becomes visible and eagerly unload them.
        // But we probably won't need to do that.
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath)
        for subview in cell.contentView.subviews {
            subview.removeFromSuperview()
        }

        guard let item = items[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return cell
        }

        if item.isSelected {
            let selectionView = UIView()
            selectionView.backgroundColor = (Theme.isDarkThemeEnabled
                ? UIColor.ows_gray75
                : UIColor.ows_gray15)
            selectionView.layer.cornerRadius = 8
            cell.contentView.addSubview(selectionView)
            selectionView.autoPinEdgesToSuperviewEdges()
        }

        let itemView = item.view
        cell.contentView.addSubview(itemView)
        itemView.autoPinEdgesToSuperviewEdges(with: UIEdgeInsets(top: cellInset, leading: cellInset, bottom: cellInset, trailing: cellInset))

        itemView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: item.accessibilityName + ".item")
        cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: item.accessibilityName + ".cell")

        return cell
    }
}
