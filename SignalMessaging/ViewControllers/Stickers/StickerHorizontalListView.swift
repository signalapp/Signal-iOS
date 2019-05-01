//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class StickerHorizontalListView: UICollectionView {

    public struct Item {
        let stickerInfo: StickerInfo
        let selectedBlock: () -> Void
    }

    public var items = [Item]() {
        didSet {
            AssertIsOnMainThread()

            collectionViewLayout.invalidateLayout()
            reloadData()
        }
    }

    private let cellReuseIdentifier = "cellReuseIdentifier"

    @objc
    public required init(cellSize: CGFloat, inset: CGFloat = 0, spacing: CGFloat = 0) {
        let layout = LinearHorizontalLayout(itemSize: CGSize(width: cellSize, height: cellSize), inset: inset, spacing: spacing)

        super.init(frame: .zero, collectionViewLayout: layout)

        delegate = self
        dataSource = self
        register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)

        setContentHuggingHorizontalLow()
        setCompressionResistanceHorizontalLow()
        autoSetDimension(.height, toSize: cellSize + 2 * inset)
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

        item.selectedBlock()
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

        // TODO: Actual size?
        let iconView = StickerView(stickerInfo: item.stickerInfo)

        cell.contentView.addSubview(iconView)
        iconView.autoPinEdgesToSuperviewEdges()

        return cell
    }
}
