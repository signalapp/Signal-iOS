//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol StickerKeyboardDelegate {
    func didSelectSticker(stickerInfo: StickerInfo)
}

// MARK: -

@objc
public class StickerKeyboard: UIStackView {

    @objc
    public weak var delegate: StickerKeyboardDelegate?

    private let headerView = UIStackView()
    private let stickerCollectionView = StickerPackCollectionView()

    private var stickerPacks = [StickerPack]()
    private var stickerPack: StickerPack? {
        didSet {
            AssertIsOnMainThread()

            stickerCollectionView.stickerPack = stickerPack
        }
    }

    @objc
    public required init() {
        super.init(frame: .zero)

        createSubviews()

        reloadStickers()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(stickersOrPacksDidChange),
                                               name: StickerManager.StickersOrPacksDidChange,
                                               object: nil)
    }

    required public init(coder: NSCoder) {
        notImplemented()
    }

    // TODO: Tune this value.
    private let keyboardHeight: CGFloat = 300

    @objc
    public override var intrinsicContentSize: CGSize {
        return CGSize(width: 0, height: keyboardHeight)
    }

    private func createSubviews() {
        axis = .vertical
        layoutMargins = .zero
        autoresizingMask = .flexibleHeight
        alignment = .fill

        addBackgroundView(withBackgroundColor: Theme.offBackgroundColor)

        addArrangedSubview(headerView)
        headerView.setContentHuggingVerticalHigh()
        headerView.setCompressionResistanceVerticalHigh()

        stickerCollectionView.stickerDelegate = self
        addArrangedSubview(stickerCollectionView)
        stickerCollectionView.setContentHuggingVerticalLow()
        stickerCollectionView.setCompressionResistanceVerticalLow()

        populateHeaderView()
    }

    private func reloadStickers() {
        stickerPacks = StickerManager.installedStickerPacks()

        packsCollectionView.collectionViewLayout.invalidateLayout()
        packsCollectionView.reloadData()

        guard stickerPacks.count > 0 else {
            stickerPack = nil
            return
        }

        if stickerPack == nil {
            stickerPack = stickerPacks.first
        }
    }

    private let packsCollectionView = UICollectionView(frame: .zero, collectionViewLayout: buildCoverLayout())
    private let cellReuseIdentifier = "cellReuseIdentifier"

    private static let packCoverSize: CGFloat = 24
    private static let packCoverSpacing: CGFloat = 12

    private class func buildCoverLayout() -> UICollectionViewLayout {
        return LinearHorizontalLayout(itemSize: CGSize(width: packCoverSize, height: packCoverSize), inset: 0, spacing: packCoverSpacing)
    }

    private func populateHeaderView() {
        headerView.spacing = StickerKeyboard.packCoverSpacing
        headerView.axis = .horizontal
        headerView.alignment = .center
        headerView.backgroundColor = Theme.offBackgroundColor
        headerView.layoutMargins = UIEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        headerView.isLayoutMarginsRelativeArrangement = true

        let searchButton = OWSButton(imageName: "search-24", tintColor: Theme.secondaryColor) { [weak self] in
            self?.searchButtonWasTapped()
        }
        searchButton.setContentHuggingHigh()
        searchButton.setCompressionResistanceHigh()
        headerView.addArrangedSubview(searchButton)

        packsCollectionView.backgroundColor = Theme.offBackgroundColor
        packsCollectionView.delegate = self
        packsCollectionView.dataSource = self
        packsCollectionView.register(UICollectionViewCell.self, forCellWithReuseIdentifier: cellReuseIdentifier)
        backgroundColor = Theme.offBackgroundColor

        packsCollectionView.setContentHuggingHorizontalLow()
        packsCollectionView.setCompressionResistanceHorizontalLow()
        packsCollectionView.autoSetDimension(.height, toSize: StickerKeyboard.packCoverSize)
        headerView.addArrangedSubview(packsCollectionView)

        let manageButton = OWSButton(imageName: "plus-24", tintColor: Theme.secondaryColor) { [weak self] in
            self?.manageButtonWasTapped()
        }
        manageButton.setContentHuggingHigh()
        manageButton.setCompressionResistanceHigh()
        headerView.addArrangedSubview(manageButton)

        updateHeaderView()
    }

    private func updateHeaderView() {
    }

    // MARK: Events

    @objc func stickersOrPacksDidChange() {
        AssertIsOnMainThread()

        Logger.verbose("")

        reloadStickers()
        updateHeaderView()
    }

    private func searchButtonWasTapped() {
        AssertIsOnMainThread()

        Logger.verbose("")

        // TODO:
    }

    private func manageButtonWasTapped() {
        AssertIsOnMainThread()

        Logger.verbose("")

        // TODO:
    }
}

// MARK: -

extension StickerKeyboard: StickerPackCollectionViewDelegate {
    public func didTapSticker(stickerInfo: StickerInfo) {
        AssertIsOnMainThread()

        Logger.verbose("")

        delegate?.didSelectSticker(stickerInfo: stickerInfo)
    }
}

// MARK: - UICollectionViewDelegate

extension StickerKeyboard: UICollectionViewDelegate {
    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        Logger.debug("")

        guard let stickerPack = stickerPacks[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }

        self.stickerPack = stickerPack
    }
}

// MARK: - UICollectionViewDataSource

extension StickerKeyboard: UICollectionViewDataSource {

    public func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection sectionIdx: Int) -> Int {
        return stickerPacks.count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // We could eventually use cells that lazy-load the sticker views
        // when the cells becomes visible and eagerly unload them.
        // But we probably won't need to do that.
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath)

        guard let stickerPack = stickerPacks[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return cell
        }

        // TODO: Actual size?
        let iconView = StickerView(stickerInfo: stickerPack.coverInfo)

        cell.contentView.addSubview(iconView)
        iconView.autoPinEdgesToSuperviewEdges()

        return cell
    }
}
