//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public protocol StickerKeyboardDelegate {
    func didSelectSticker(stickerInfo: StickerInfo)
    func presentManageStickersView()
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

            // We use nil for the "recents" special-case.
            if let stickerPack = stickerPack {
                stickerCollectionView.showInstalledPack(stickerPack: stickerPack)
            } else {
                stickerCollectionView.showRecents()
            }
        }
    }

    @objc
    public required init() {
        super.init(frame: .zero)

        createSubviews()

        reloadStickers()

        // By default, show the "recent" stickers.
        assert(nil == stickerPack)
        stickerCollectionView.showRecents()

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

        let packItems = stickerPacks.map { (stickerPack) in
            StickerHorizontalListView.Item(stickerInfo: stickerPack.coverInfo) { [weak self] in
                self?.stickerPack = stickerPack
            }
        }
        packsCollectionView.items = packItems

        guard stickerPacks.count > 0 else {
            stickerPack = nil
            return
        }
    }

    private static let packCoverSize: CGFloat = 24
    private static let packCoverSpacing: CGFloat = 12
    private let packsCollectionView = StickerHorizontalListView(cellSize: StickerKeyboard.packCoverSize, spacing: StickerKeyboard.packCoverSpacing)

    private func populateHeaderView() {
        backgroundColor = Theme.offBackgroundColor

        headerView.spacing = StickerKeyboard.packCoverSpacing
        headerView.axis = .horizontal
        headerView.alignment = .center
        headerView.backgroundColor = Theme.offBackgroundColor
        headerView.layoutMargins = UIEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        headerView.isLayoutMarginsRelativeArrangement = true

        if FeatureFlags.stickerSearch {
            let searchButton = buildHeaderButton("search-24") { [weak self] in
                self?.searchButtonWasTapped()
            }
            headerView.addArrangedSubview(searchButton)
        }

        let recentsButton = buildHeaderButton("recent-outline-24") { [weak self] in
            self?.recentsButtonWasTapped()
        }
        headerView.addArrangedSubview(recentsButton)

        packsCollectionView.backgroundColor = Theme.offBackgroundColor
        headerView.addArrangedSubview(packsCollectionView)

        let manageButton = buildHeaderButton("plus-24") { [weak self] in
            self?.manageButtonWasTapped()
        }
        headerView.addArrangedSubview(manageButton)

        updateHeaderView()
    }

    private func buildHeaderButton(_ imageName: String, block: @escaping () -> Void) -> UIView {
        let button = OWSButton(imageName: imageName, tintColor: Theme.secondaryColor, block: block)
        button.setContentHuggingHigh()
        button.setCompressionResistanceHigh()
        return button
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

    private func recentsButtonWasTapped() {
        AssertIsOnMainThread()

        Logger.verbose("")

        // nil is used for the recents special-case.
        stickerPack = nil
    }

    private func manageButtonWasTapped() {
        AssertIsOnMainThread()

        Logger.verbose("")

        delegate?.presentManageStickersView()
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
