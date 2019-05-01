//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class StickerHorizontalListViewItem: NSObject {
    let stickerInfo: StickerInfo
    let selectedBlock: () -> Void

    @objc
    public init(stickerInfo: StickerInfo, selectedBlock: @escaping () -> Void) {
        self.stickerInfo = stickerInfo
        self.selectedBlock = selectedBlock
    }
}

// MARK: -

@objc
public class StickerHorizontalListView: UICollectionView {

    private let cellSize: CGFloat

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
    public required init(cellSize: CGFloat, spacing: CGFloat = 0) {
        self.cellSize = cellSize
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

        let stickerView = StickerView(stickerInfo: item.stickerInfo)
        cell.contentView.addSubview(stickerView)
        stickerView.autoPinEdgesToSuperviewEdges()

        return cell
    }
}
