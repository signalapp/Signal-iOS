//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

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
    public convenience init(
        stickerInfo: StickerInfo,
        didSelectBlock: @escaping () -> Void,
        cache: StickerViewCache? = nil
    ) {
        self.init(stickerInfo: stickerInfo, didSelectBlock: didSelectBlock, isSelectedBlock: { false }, cache: cache)
    }

    public init(
        stickerInfo: StickerInfo,
        didSelectBlock: @escaping () -> Void,
        isSelectedBlock: @escaping () -> Bool,
        cache: StickerViewCache? = nil
    ) {
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

    public init(
        didSelectBlock: @escaping () -> Void,
        isSelectedBlock: @escaping () -> Bool
    ) {
        self.didSelectBlock = didSelectBlock
        self.isSelectedBlock = isSelectedBlock
    }

    public var view: UIView {
        let imageView = UIImageView(image: UIImage(named: "recent"))
        imageView.tintColor = .Signal.label
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
    private let cellContentInset: CGFloat

    public typealias Item = StickerHorizontalListViewItem

    public var items = [Item]() {
        didSet {
            AssertIsOnMainThread()

            collectionViewLayout.invalidateLayout()
            reloadData()
        }
    }

    private var cellRegistration: UICollectionView.CellRegistration<UICollectionViewCell, Item>!

    public init(cellSize: CGFloat, cellContentInset: CGFloat, spacing: CGFloat) {
        self.cellSize = cellSize
        self.cellContentInset = cellContentInset

        let layout = LinearHorizontalLayout(
            configuration: .init(itemSize: CGSize(square: cellSize), minimumInteritemSpacing: spacing)
        )

        super.init(frame: .zero, collectionViewLayout: layout)

        let selectedBackgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.2)
            : UIColor(white: 0, alpha: 0.12)
        }

        cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Item>
        { cell, indexPath, item in

            // Remove previous content.
            cell.contentView.removeAllSubviews()

            // Add custom view to the cell.
            let itemView = item.view
            itemView.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(itemView)
            NSLayoutConstraint.activate([
                itemView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: cellContentInset),
                itemView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: cellContentInset),
                itemView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -cellContentInset),
                itemView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -cellContentInset),
            ])

            // Configure background - this closure is called whenever cell state changes.
            cell.configurationUpdateHandler = { cell, state in
                var background = UIBackgroundConfiguration.clear()
                background.cornerRadius = cellSize / 2
                if item.isSelected {
                    background.backgroundColor = selectedBackgroundColor
                } else {
                    background.backgroundColor = .clear
                }
                cell.backgroundConfiguration = background
            }
        }

        backgroundColor = .clear
        delegate = self
        dataSource = self
        showsHorizontalScrollIndicator = false

        setContentHuggingHorizontalLow()
        setCompressionResistanceHorizontalLow()
    }

    required public init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Reload visible items to refresh the "selected" state
    func updateSelections(scrollToSelectedItem: Bool = false) {
        reloadData()
        guard scrollToSelectedItem else { return }
        guard let (selectedIndex, _) = items.enumerated().first(where: { $1.isSelected }) else { return }
        scrollToItem(at: IndexPath(row: selectedIndex, section: 0), at: .centeredHorizontally, animated: true)
    }
}

// MARK: - UICollectionViewDelegate

extension StickerHorizontalListView: UICollectionViewDelegate {

    public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let item = items[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return
        }

        item.didSelectBlock()
        reloadItems(at: [indexPath])
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

        guard let item = items[safe: indexPath.row] else {
            owsFailDebug("Invalid index path: \(indexPath)")
            return UICollectionViewCell()
        }

        return collectionView.dequeueConfiguredReusableCell(
            using: cellRegistration,
            for: indexPath,
            item: item
        )
    }
}

// A trivial layout that places each item in a horizontal line.
// Each item has uniform size.
private class LinearHorizontalLayout: UICollectionViewLayout {

    struct Configuration {
        var itemSize: CGSize
        var itemSpacing: CGFloat

        init(
            itemSize: CGSize,
            minimumInteritemSpacing: CGFloat = 8,
        ) {
            self.itemSize = itemSize
            self.itemSpacing = minimumInteritemSpacing
        }
    }

    // MARK: - Properties

    private let configuration: Configuration

    private var cachedAttributes: [UICollectionViewLayoutAttributes] = []

    private var contentWidth: CGFloat = 0

    override var flipsHorizontallyInOppositeLayoutDirection: Bool {
        true
    }

    override var collectionViewContentSize: CGSize {
        guard let collectionView else { return .zero }

        return CGSize(
            width: contentWidth,
            height: collectionView.bounds.height - collectionView.contentInset.totalHeight
        )
    }

    // MARK: Initializers

    @available(*, unavailable, message: "use other constructor instead.")
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(configuration: Configuration) {
        self.configuration = configuration

        super.init()
    }

    // MARK: Methods

    override func invalidateLayout() {
        super.invalidateLayout()

        cachedAttributes.removeAll()
        contentWidth = 0
    }

    override func invalidateLayout(with context: UICollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: context)

        cachedAttributes.removeAll()
        contentWidth = 0
    }

    override func prepare() {
        super.prepare()

        guard let collectionView, cachedAttributes.isEmpty else { return }

        guard collectionView.numberOfSections == 1 else {
            owsFailDebug("This layout only support a single section.")
            return
        }
        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else { return }

        let itemSize = configuration.itemSize
        let spacing = configuration.itemSpacing

        // Calculate vertical centering
        let collectionViewHeight = collectionView.bounds.height - collectionView.contentInset.totalHeight
        let yPosition = (collectionViewHeight - itemSize.height) / 2

        var xPosition: CGFloat = 0

        // Create attributes for each item
        for item in 0..<itemCount {
            let indexPath = IndexPath(item: item, section: 0)
            let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)

            attributes.frame = CGRect(
                x: xPosition,
                y: yPosition,
                width: itemSize.width,
                height: itemSize.height
            )

            cachedAttributes.append(attributes)

            xPosition += itemSize.width + spacing
        }

        // Remove trailing spacing and add trailing inset
        contentWidth = xPosition - spacing
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        cachedAttributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        cachedAttributes[safe: indexPath.row]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        guard let collectionView else { return false }
        return newBounds.height != collectionView.bounds.height
    }
}
