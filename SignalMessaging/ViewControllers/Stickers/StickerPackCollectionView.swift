//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol StickerPackCollectionViewDelegate {
    func didTapSticker(stickerInfo: StickerInfo)
    func stickerPreviewHostView() -> UIView?
    func stickerPreviewHasOverlay() -> Bool
}

// MARK: -

@objc
public class StickerPackCollectionView: UICollectionView {

    private var stickerPackDataSource: StickerPackDataSource? {
        didSet {
            AssertIsOnMainThread()

            stickerPackDataSource?.add(delegate: self)

            reloadStickers()

            // Scroll to the top.
            contentOffset = .zero
        }
    }

    private var stickerInfos = [StickerInfo]()

    public var stickerCount: Int {
        return stickerInfos.count
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

        isUserInteractionEnabled = true
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress)))
    }

    // MARK: Modes

    @objc
    public func showInstalledPack(stickerPack: StickerPack) {
        AssertIsOnMainThread()

        self.stickerPackDataSource = InstalledStickerPackDataSource(stickerPackInfo: stickerPack.info)
    }

    @objc
    public func showUninstalledPack(stickerPack: StickerPack) {
        AssertIsOnMainThread()

        self.stickerPackDataSource = TransientStickerPackDataSource(stickerPackInfo: stickerPack.info,
                                                                    shouldDownloadAllStickers: true)
    }

    @objc
    public func showRecents() {
        AssertIsOnMainThread()

        self.stickerPackDataSource = RecentStickerPackDataSource()
    }

    public func showInstalledPackOrRecents(stickerPack: StickerPack?) {
        if let stickerPack = stickerPack {
            showInstalledPack(stickerPack: stickerPack)
        } else {
            showRecents()
        }
    }

    func show(dataSource: StickerPackDataSource) {
        AssertIsOnMainThread()

        self.stickerPackDataSource = dataSource
    }

    // MARK: Events

    required public init(coder: NSCoder) {
        notImplemented()
    }

    private func reloadStickers() {
        AssertIsOnMainThread()

        guard let stickerPackDataSource = stickerPackDataSource else {
            stickerInfos = []
            return
        }

        stickerInfos = stickerPackDataSource.installedStickerInfos

        reloadData()
    }

    @objc
    func handleLongPress(sender: UIGestureRecognizer) {
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
        guard let indexPath = self.indexPathForItem(at: sender.location(in: self)) else { return }
        guard let stickerInfo = stickerInfos[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }

        ensurePreview(stickerInfo: stickerInfo)
    }

    private var previewView: UIView?
    private var previewStickerInfo: StickerInfo?

    private func hidePreview() {
        AssertIsOnMainThread()

        previewView?.removeFromSuperview()
        previewView = nil
        previewStickerInfo = nil
    }

    private func ensurePreview(stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        if previewView != nil,
            let previewStickerInfo = previewStickerInfo,
            previewStickerInfo == stickerInfo {
            // Already showing a preview for this sticker.
            return
        }

        hidePreview()

        guard let stickerView = imageView(forStickerInfo: stickerInfo) else {
            owsFailDebug("Couldn't load sticker for display")
            return
        }
        guard let stickerDelegate = stickerDelegate else {
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
        guard let stickerPackDataSource = stickerPackDataSource else {
            owsFailDebug("Missing stickerPackDataSource.")
            return nil
        }
        return StickerView.stickerView(forStickerInfo: stickerInfo, dataSource: stickerPackDataSource)
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
        for subview in cell.contentView.subviews {
            subview.removeFromSuperview()
        }

        guard let stickerInfo = stickerInfos[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return cell
        }
        guard let stickerView = imageView(forStickerInfo: stickerInfo) else {
            owsFailDebug("Couldn't load sticker for display")
            return cell
        }

        cell.contentView.addSubview(stickerView)
        stickerView.autoPinEdgesToSuperviewEdges()

        let accessibilityName = "sticker." + stickerInfo.asKey()
        cell.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: accessibilityName + ".cell")
        stickerView.accessibilityIdentifier = UIView.accessibilityIdentifier(in: self, name: accessibilityName + ".item")

        return cell
    }
}

// MARK: - Layout

extension StickerPackCollectionView {

    // TODO:
    static let kSpacing: CGFloat = 8

    private class func buildLayout() -> UICollectionViewFlowLayout {
        let layout = UICollectionViewFlowLayout()

        layout.sectionInsetReference = .fromSafeArea
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

        let containerWidth = self.safeAreaLayoutGuide.layoutFrame.size.width

        let spacing = StickerPackCollectionView.kSpacing
        let inset = spacing
        let preferredCellSize: CGFloat = 80
        let contentWidth = containerWidth - 2 * inset
        let columnCount = UInt((contentWidth + spacing) / (preferredCellSize + spacing))
        let cellWidth = (contentWidth - spacing * (CGFloat(columnCount) - 1)) / CGFloat(columnCount)
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
        AssertIsOnMainThread()

        reloadStickers()
    }
}
