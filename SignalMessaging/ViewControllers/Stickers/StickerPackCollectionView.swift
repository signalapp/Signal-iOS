//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import YYImage

@objc
public protocol StickerPackCollectionViewDelegate {
    func didTapSticker(stickerInfo: StickerInfo)
}

// MARK: -

@objc
public class StickerPackCollectionView: UICollectionView {

    private var stickerInfos = [StickerInfo]()

    public var stickerPack: StickerPack? {
        didSet {
            AssertIsOnMainThread()

            reloadStickers()
            // Scroll to the top.
            contentOffset = .zero
        }
    }

    @objc
    public weak var stickerDelegate: StickerPackCollectionViewDelegate?

    @objc
    override public var frame: CGRect {
        didSet {
            updateLayout()
        }
    }

    @objc
    override public var bounds: CGRect {
        didSet {
            updateLayout()
        }
    }

    private let cellReuseIdentifier = "cellReuseIdentifier"

    @objc
    public required init() {
        super.init(frame: .zero, collectionViewLayout: StickerPackCollectionView.buildLayout())

        delegate = self
        dataSource = self
        register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        backgroundColor = Theme.offBackgroundColor

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.StickersOrPacksDidChange,
                                               object: nil)
    }

    // MARK: Events

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        reloadStickers()
    }

    required public init(coder: NSCoder) {
        notImplemented()
    }

    private func reloadStickers() {
        AssertIsOnMainThread()

        if let stickerPack = stickerPack {
            // Only show installed stickers.
            stickerInfos = StickerManager.installedStickers(forStickerPack: stickerPack)

            // Download any missing stickers.
            StickerManager.ensureDownloadsAsync(forStickerPack: stickerPack)
        } else {
            stickerInfos = []
        }

        reloadData()
    }
}

// MARK: - UICollectionViewDelegate

extension StickerPackCollectionView: UICollectionViewDelegate {
     public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.debug("")

        guard let stickerInfo = stickerInfos[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }

        self.stickerDelegate?.didTapSticker(stickerInfo: stickerInfo)
    }
}

// MARK: - UICollectionViewDataSource

extension StickerPackCollectionView: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        return stickerInfos.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // We could eventually use cells that lazy-load the sticker views
        // when the cells becomes visible and eagerly unload them.
        // But we probably won't need to do that.
        let cell = dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath)

        guard let stickerInfo = stickerInfos[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return cell
        }

        // TODO: Actual size?
        let iconView = StickerView(stickerInfo: stickerInfo)

        cell.contentView.addSubview(iconView)
        iconView.autoPinEdgesToSuperviewEdges()

        return cell
    }
}

// MARK: - Layout

extension StickerPackCollectionView {

    // TODO:
    static let kSpacing: CGFloat = 8

    private class func buildLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()

        if #available(iOS 11, *) {
            layout.sectionInsetReference = .fromSafeArea
        }
        layout.minimumInteritemSpacing = kSpacing
        layout.minimumLineSpacing = kSpacing
        let inset = kSpacing
        layout.sectionInset = UIEdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset)

        return layout
    }

    // TODO: There's pending design Qs here.
    func updateLayout() {
        guard let flowLayout = collectionViewLayout as? UICollectionViewFlowLayout else {
            // The layout isn't set while the view is being initialized.
            return
        }

        let containerWidth: CGFloat
        if #available(iOS 11.0, *) {
            containerWidth = self.safeAreaLayoutGuide.layoutFrame.size.width
        } else {
            containerWidth = self.frame.size.width
        }

        let spacing = StickerPackCollectionView.kSpacing
        let inset = spacing
        let preferredCellSize: CGFloat = 80
        let contentWidth = containerWidth - 2 * inset
        let columnCount = UInt((contentWidth + spacing) / (preferredCellSize + spacing))
        let cellWidth = (contentWidth - spacing * (CGFloat(columnCount) - 1)) / CGFloat(columnCount)
        let itemSize = CGSize(width: cellWidth, height: cellWidth)

        if (itemSize != flowLayout.itemSize) {
            flowLayout.itemSize = itemSize
            flowLayout.invalidateLayout()
        }
    }
}
