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
        }
    }

    @objc
    public weak var stickerDelegate: StickerPackCollectionViewDelegate?

    @objc
    override public var frame: CGRect {
        didSet {
            Logger.verbose("----- frame: \(frame), bounds: \(bounds)")
            Logger.flush()
            updateLayout()
        }
    }

    @objc
    override public var bounds: CGRect {
        didSet {
            Logger.verbose("----- frame: \(frame), bounds: \(bounds)")
            Logger.flush()
            updateLayout()
        }
    }

    private let cellReuseIdentifier = "cellReuseIdentifier"

    @objc
    public required init() {
        super.init(frame: .zero, collectionViewLayout: StickerPackCollectionView.buildLayout())

        self.delegate = self
        self.dataSource = self
        register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)

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

        Logger.verbose("---- stickerInfos: \(stickerInfos.count)")

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

    // TODO: Show the share button using this?
//    override public func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
//
//        let defaultView = UICollectionReusableView()
//
//        return defaultView
//    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        Logger.debug("indexPath: \(indexPath)")

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

        cell.backgroundColor = .blue
        cell.contentView.backgroundColor = .blue
        iconView.backgroundColor = .green

        return cell
    }
}

// MARK: - Layout

extension StickerPackCollectionView {

    // TODO:
    static let kInterItemSpacing: CGFloat = 0

    private class func buildLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()

        if #available(iOS 11, *) {
            layout.sectionInsetReference = .fromSafeArea
        }
        layout.minimumInteritemSpacing = kInterItemSpacing
        layout.minimumLineSpacing = kInterItemSpacing

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

        let preferredCellSize = 100
        let columnCount = UInt(containerWidth / CGFloat(preferredCellSize))
        let cellWidth = containerWidth / CGFloat(columnCount)
        let itemSize = CGSize(width: cellWidth, height: cellWidth)

        Logger.verbose("itemSize: \(itemSize)")

        if (itemSize != flowLayout.itemSize) {
            flowLayout.itemSize = itemSize
            flowLayout.invalidateLayout()
        }
    }
}
