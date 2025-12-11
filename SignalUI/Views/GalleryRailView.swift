//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

public protocol GalleryRailItemProvider: AnyObject {
    var railItems: [GalleryRailItem] { get }
}

public protocol GalleryRailItem {
    func buildRailItemView() -> UIView
    func isEqualToGalleryRailItem(_ other: GalleryRailItem?) -> Bool
}

public extension GalleryRailItem where Self: Equatable {
    func isEqualToGalleryRailItem(_ other: GalleryRailItem?) -> Bool {
        guard let other = other as? Self else {
            return false
        }
        return self == other
    }
}

protocol GalleryRailCellViewDelegate: AnyObject {
    func didTapGalleryRailCellView(_ galleryRailCellView: GalleryRailCellView)
}

public struct GalleryRailCellConfiguration {
    public let cornerRadius: CGFloat

    public let itemBorderWidth: CGFloat
    public let itemBorderColor: UIColor?

    public let focusedItemBorderWidth: CGFloat
    public let focusedItemBorderColor: UIColor?
    public let focusedItemOverlayColor: UIColor?
    public let focusedItemExtraPadding: CGFloat

    public static var empty: GalleryRailCellConfiguration {
        GalleryRailCellConfiguration(
            cornerRadius: 0,
            itemBorderWidth: 0,
            itemBorderColor: nil,
            focusedItemBorderWidth: 0,
            focusedItemBorderColor: nil,
            focusedItemOverlayColor: nil
        )
    }

    public init(
        cornerRadius: CGFloat,
        itemBorderWidth: CGFloat,
        itemBorderColor: UIColor?,
        focusedItemBorderWidth: CGFloat,
        focusedItemBorderColor: UIColor?,
        focusedItemOverlayColor: UIColor?,
        focusedItemExtraPadding: CGFloat = 0
    ) {
        self.cornerRadius = cornerRadius
        self.itemBorderWidth = itemBorderWidth
        self.itemBorderColor = itemBorderColor
        self.focusedItemBorderWidth = focusedItemBorderWidth
        self.focusedItemBorderColor = focusedItemBorderColor
        self.focusedItemOverlayColor = focusedItemOverlayColor
        self.focusedItemExtraPadding = focusedItemExtraPadding
    }
}

public class GalleryRailCellView: UIView {

    weak var delegate: GalleryRailCellViewDelegate?

    let configuration: GalleryRailCellConfiguration

    private let contentContainer = UIView()

    private let dimmerView = UIView()

    public init(configuration: GalleryRailCellConfiguration = .empty) {
        self.configuration = configuration

        super.init(frame: .zero)

        clipsToBounds = false
        directionalLayoutMargins = .zero

        contentContainer.clipsToBounds = true
        contentContainer.layer.cornerRadius = configuration.cornerRadius
        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)
        contentContainer.autoPinEdgesToSuperviewMargins()

        dimmerView.layer.cornerRadius = configuration.cornerRadius
        dimmerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dimmerView)

        NSLayoutConstraint.activate([
            contentContainer.widthAnchor.constraint(equalTo: contentContainer.heightAnchor),

            contentContainer.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),

            dimmerView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            dimmerView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            dimmerView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            dimmerView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(sender:)))
        addGestureRecognizer(tapGesture)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Actions

    @objc
    private func didTap(sender: UITapGestureRecognizer) {
        delegate?.didTapGalleryRailCellView(self)
    }

    private(set) var item: GalleryRailItem?

    func configure(item: GalleryRailItem, delegate: GalleryRailCellViewDelegate) {
        self.item = item
        self.delegate = delegate

        for view in contentContainer.subviews {
            view.removeFromSuperview()
        }

        let itemView = item.buildRailItemView()
        itemView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(itemView)
        NSLayoutConstraint.activate([
            itemView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            itemView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            itemView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            itemView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    // MARK: Selected

    var isCellFocused: Bool = false {
        didSet {
            let borderWidth = isCellFocused ? configuration.focusedItemBorderWidth : configuration.itemBorderWidth
            dimmerView.layer.borderWidth = borderWidth

            let borderColor = isCellFocused ? configuration.focusedItemBorderColor : configuration.itemBorderColor
            dimmerView.layer.borderColor = borderColor?.cgColor

            let dimmerColor = isCellFocused ? configuration.focusedItemOverlayColor : nil
            dimmerView.backgroundColor = dimmerColor

            let horizontalMargin: CGFloat = isCellFocused ? configuration.focusedItemExtraPadding : 0
            directionalLayoutMargins.leading = horizontalMargin
            directionalLayoutMargins.trailing = horizontalMargin
        }
    }
}

public protocol GalleryRailViewDelegate: AnyObject {
    func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem)
}

public class GalleryRailView: UIView, GalleryRailCellViewDelegate {

    public weak var delegate: GalleryRailViewDelegate?

    private(set) var cellViews: [GalleryRailCellView] = []

    public var isScrollEnabled: Bool {
        get { scrollView.isScrollEnabled }
        set { scrollView.isScrollEnabled = newValue }
    }

    public var itemSize: CGFloat = 40 {
        didSet {
            if let stackViewHeightConstraint {
                stackViewHeightConstraint.constant = itemSize
            }
            setNeedsLayout()
        }
    }

    // MARK: UIView

    override init(frame: CGRect) {
        super.init(frame: frame)

        clipsToBounds = false
        preservesSuperviewLayoutMargins = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            // Constrain width to view and not layout guide because as of iOS 16.4
            // UIStackView, that GalleryRailView is placed in, was messing with view's layout margins.
            scrollView.frameLayoutGuide.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.frameLayoutGuide.trailingAnchor.constraint(equalTo: trailingAnchor),
            // Constrain height to margins because view controller adjusts those to control view spacing.
            scrollView.frameLayoutGuide.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            scrollView.frameLayoutGuide.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
        ])
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateScrollViewContentInsetsIfNecessary()
        scrollToFocusedCell(animated: false)
    }

    public func configureCellViews(
        itemProvider: GalleryRailItemProvider,
        focusedItem: GalleryRailItem,
        cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView,
        animated: Bool = true
    ) {
        let areRailItemsIdentical = { (lhs: [GalleryRailItem], rhs: [GalleryRailItem]) -> Bool in
            guard lhs.count == rhs.count else {
                return false
            }
            for (index, element) in lhs.enumerated() {
                guard element.isEqualToGalleryRailItem(rhs[index]) else {
                    return false
                }
            }
            return true
        }

        let currentRailItems = cellViews.compactMap { $0.item }
        if itemProvider === self.itemProvider, areRailItemsIdentical(itemProvider.railItems, currentRailItems) {
            updateFocusedItem(focusedItem, animated: animated)
            return
        }

        self.itemProvider = itemProvider

        if let stackView {
            stackView.removeFromSuperview()
        }

        cellViews = buildCellViews(items: itemProvider.railItems, cellViewBuilder: cellViewBuilder)
        let stackView = installNewStackView(arrangedSubviews: cellViews)
        let heightConstraint = stackView.heightAnchor.constraint(equalToConstant: itemSize)
        heightConstraint.isActive = true
        stackView.layoutIfNeeded()
        self.stackView = stackView
        self.stackViewHeightConstraint = heightConstraint

        UIView.performWithoutAnimation {
            layoutIfNeeded()
        }

        updateFocusedItem(focusedItem, animated: animated)
    }

    // MARK: GalleryRailCellViewDelegate

    func didTapGalleryRailCellView(_ galleryRailCellView: GalleryRailCellView) {
        guard let item = galleryRailCellView.item else {
            owsFailDebug("item was unexpectedly nil")
            return
        }

        delegate?.galleryRailView(self, didTapItem: item)
    }

    // MARK: Subview Helpers

    private var itemProvider: GalleryRailItemProvider?

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.isScrollEnabled = true
        scrollView.clipsToBounds = false
        scrollView.layoutMargins = .zero
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        return scrollView
    }()
    private var lastKnownScrollViewWidth: CGFloat = 0

    private var stackView: UIStackView?

    private func installNewStackView(arrangedSubviews: [UIView]) -> UIStackView {
        let stackView = UIStackView(arrangedSubviews: arrangedSubviews)
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        return stackView
    }
    private var stackViewHeightConstraint: NSLayoutConstraint?

    private func buildCellViews(
        items: [GalleryRailItem],
        cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView
    ) -> [GalleryRailCellView] {
        return items.map { item in
            let cellView = cellViewBuilder(item)
            cellView.configure(item: item, delegate: self)
            return cellView
        }
    }

    enum ScrollFocusMode {
        case keepCentered, keepWithinBounds
    }

    var scrollFocusMode: ScrollFocusMode = .keepCentered {
        didSet {
            if oldValue != scrollFocusMode {
                setNeedsUpdateScrollViewContentInsets()
                updateScrollViewContentInsetsIfNecessary()
            }
        }
    }

    private func setNeedsUpdateScrollViewContentInsets() {
        lastKnownScrollViewWidth = 0
    }

    private func updateScrollViewContentInsetsIfNecessary() {
        guard let stackView, stackView.frame.width > 0, scrollView.frame.width > 0  else { return }

        let scrollViewWidth = scrollView.frame.width
        guard scrollViewWidth != lastKnownScrollViewWidth else { return }

        switch scrollFocusMode {
        case .keepCentered:
            // Shrink scroll view viewport area to a size of one cell view, centered horizontally.
            let horizontalContentInset = 0.5 * (scrollViewWidth - itemSize)
            scrollView.contentInset.left = horizontalContentInset
            scrollView.contentInset.right = horizontalContentInset

        case .keepWithinBounds:
            scrollView.contentInset.left = 0
            scrollView.contentInset.right = 0
        }

        lastKnownScrollViewWidth = scrollViewWidth
    }

    private func updateFocusedItem(_ focusedItem: GalleryRailItem, animated: Bool) {
        guard !cellViews.isEmpty else { return }

        cellViews.forEach { cellView in
            if let item = cellView.item, item.isEqualToGalleryRailItem(focusedItem) {
                cellView.isCellFocused = true
            } else {
                cellView.isCellFocused = false
            }
        }
        stackView?.layoutIfNeeded()
        scrollToFocusedCell(animated: animated)
    }

    private func scrollToFocusedCell(animated: Bool) {
        guard let focusedCell = cellViews.first(where: { $0.isCellFocused }) else { return }
        // Scroll view's "viewport" area size doesn't consider extra padding focused cell might have.
        // Adjust content offset accordingly.
        let cellFrame = focusedCell.convert(focusedCell.bounds, to: scrollView)
        let extraPadding = focusedCell.configuration.focusedItemExtraPadding
        let contentOffsetX = cellFrame.minX + extraPadding - scrollView.contentInset.left
        scrollView.setContentOffset(.init(x: contentOffsetX, y: 0), animated: animated)
    }
}
