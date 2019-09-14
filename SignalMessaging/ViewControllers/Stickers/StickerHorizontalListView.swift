//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol StickerHorizontalListViewItem {
    var view: UIView { get }
    var didSelectBlock: () -> Void { get }
    var isSelected: Bool { get }
    var accessibilityName: String { get }
}

// MARK: -

@objc
public class StickerHorizontalListViewItemSticker: NSObject, StickerHorizontalListViewItem {
    private let stickerInfo: StickerInfo
    public let didSelectBlock: () -> Void
    public let isSelectedBlock: () -> Bool

    // This initializer can be used for cells which are never selected.
    @objc
    public init(stickerInfo: StickerInfo, didSelectBlock: @escaping () -> Void) {
        self.stickerInfo = stickerInfo
        self.didSelectBlock = didSelectBlock
        self.isSelectedBlock = {
            false
        }
    }

    @objc
    public init(stickerInfo: StickerInfo, didSelectBlock: @escaping () -> Void, isSelectedBlock: @escaping () -> Bool) {
        self.stickerInfo = stickerInfo
        self.didSelectBlock = didSelectBlock
        self.isSelectedBlock = isSelectedBlock
    }

    public var view: UIView {
        let view = StickerView(stickerInfo: stickerInfo)
        view.layer.minificationFilter = .trilinear
        return view
    }

    public var isSelected: Bool {
        return isSelectedBlock()
    }

    public var accessibilityName: String {
        // We just need a stable identifier.
        return "pack." + stickerInfo.asKey()
    }
}

// MARK: -

@objc
public class StickerHorizontalListViewItemRecents: NSObject, StickerHorizontalListViewItem {
    public let didSelectBlock: () -> Void
    public let isSelectedBlock: () -> Bool

    @objc
    public init(didSelectBlock: @escaping () -> Void, isSelectedBlock: @escaping () -> Bool) {
        self.didSelectBlock = didSelectBlock
        self.isSelectedBlock = isSelectedBlock
    }

    public var view: UIView {
        let imageView = UIImageView()
        imageView.setTemplateImageName("recent-outline-24", tintColor: Theme.secondaryColor)
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

@objc
public class StickerHorizontalListView: UICollectionView {

    private let cellSize: CGFloat
    private let cellInset: CGFloat

    public typealias Item = StickerHorizontalListViewItem

    @objc
    public var items = [Item]() {
        didSet {
            AssertIsOnMainThread()

            collectionViewLayout.invalidateLayout()
            reloadData()
        }
    }

    private let cellReuseIdentifier = "cellReuseIdentifier"

    @objc
    public override var contentInset: UIEdgeInsets {
        didSet {
            updateHeightConstraint()
        }
    }

    private var heightConstraint: NSLayoutConstraint?

    @objc
    public required init(cellSize: CGFloat, cellInset: CGFloat, spacing: CGFloat = 0) {
        self.cellSize = cellSize
        self.cellInset = cellInset
        let layout = LinearHorizontalLayout(itemSize: CGSize(width: cellSize, height: cellSize), spacing: spacing)

        super.init(frame: .zero, collectionViewLayout: layout)

        delegate = self
        dataSource = self
        register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)

        setContentHuggingHorizontalLow()
        setCompressionResistanceHorizontalLow()
        heightConstraint = autoSetDimension(.height, toSize: 0)
        updateHeightConstraint()
    }

    // Reload visible items to refresh the "selected" state
    func updateSelections() {
        reloadItems(at: indexPathsForVisibleItems)
    }

    private func updateHeightConstraint() {
        guard let heightConstraint = heightConstraint else {
            owsFailDebug("Missing heightConstraint.")
            return
        }
        let newValue = cellSize + contentInset.top + contentInset.bottom
        if heightConstraint.constant == newValue {
            return
        }
        heightConstraint.constant = newValue
        invalidateIntrinsicContentSize()
    }

    required public init(coder: NSCoder) {
        notImplemented()
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
                : UIColor.ows_gray10)
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
