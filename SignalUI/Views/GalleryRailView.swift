//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

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
        focusedItemOverlayColor: UIColor?
    ) {
        self.cornerRadius = cornerRadius
        self.itemBorderWidth = itemBorderWidth
        self.itemBorderColor = itemBorderColor
        self.focusedItemBorderWidth = focusedItemBorderWidth
        self.focusedItemBorderColor = focusedItemBorderColor
        self.focusedItemOverlayColor = focusedItemOverlayColor
    }
}

public class GalleryRailCellView: UIView {

    weak var delegate: GalleryRailCellViewDelegate?

    private let configuration: GalleryRailCellConfiguration

    public init(configuration: GalleryRailCellConfiguration = .empty) {
        self.configuration = configuration

        super.init(frame: .zero)

        layoutMargins = .zero
        clipsToBounds = false
        addSubview(contentContainer)
        contentContainer.autoPinEdgesToSuperviewMargins()
        contentContainer.layer.cornerRadius = configuration.cornerRadius

        dimmerView.layer.cornerRadius = configuration.cornerRadius
        addSubview(dimmerView)
        dimmerView.autoPinEdges(toEdgesOf: contentContainer)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(sender:)))
        addGestureRecognizer(tapGesture)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Actions

    @objc
    func didTap(sender: UITapGestureRecognizer) {
        delegate?.didTapGalleryRailCellView(self)
    }

    // MARK: 

    var item: GalleryRailItem?

    func configure(item: GalleryRailItem, delegate: GalleryRailCellViewDelegate) {
        self.item = item
        self.delegate = delegate

        for view in contentContainer.subviews {
            view.removeFromSuperview()
        }

        let itemView = item.buildRailItemView()
        contentContainer.addSubview(itemView)
        itemView.autoPinEdgesToSuperviewEdges()
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
        }
    }

    // MARK: Subview Helpers

    private let contentContainer: UIView = {
        let view = UIView()
        view.autoPinToSquareAspectRatio()
        view.clipsToBounds = true
        return view
    }()

    private let dimmerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
}

public protocol GalleryRailViewDelegate: AnyObject {
    func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem)
}

public class GalleryRailView: UIView, GalleryRailCellViewDelegate {

    public weak var delegate: GalleryRailViewDelegate?

    private(set) var cellViews: [GalleryRailCellView] = []

    /**
     * If enabled, `GalleryRailView` will hide itself if there is less than two items.
     */
    public var hidesAutomatically = true {
        didSet {
            guard let itemProvider else { return }
            // Unhide automatically if there's more than 1 item.
            if hidesAutomatically && isHiddenInStackView && itemProvider.railItems.count > 1 {
                isHiddenInStackView = false
            }
        }
    }

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

        addSubview(scrollView)
        // Constrain width to view and not layout guide because as of iOS 16.4
        // UIStackView, that GalleryRailView is placed in, was messing with view's layout margins.
        scrollView.autoPinWidthToSuperview()
        // Constrain height to margins because view controller adjusts those to control view spacing.
        scrollView.autoPinHeightToSuperviewMargins()
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

        let duration: TimeInterval = animated ? 0.2 : 0

        guard itemProvider.railItems.count > 1 || !hidesAutomatically else {
            guard !isHiddenInStackView else { return }

            let existingStackView = stackView
            if animated {
                UIView.animate(
                    withDuration: duration,
                    animations: {
                        self.isHiddenInStackView = true
                    },
                    completion: { _ in
                        existingStackView?.removeFromSuperview()
                    }
                )
            } else {
                existingStackView?.removeFromSuperview()
                isHiddenInStackView = true
            }
            cellViews = []
            return
        }

        if let stackView {
            stackView.removeFromSuperview()
        }

        cellViews = buildCellViews(items: itemProvider.railItems, cellViewBuilder: cellViewBuilder)
        let stackView = installNewStackView(arrangedSubviews: cellViews)
        stackViewHeightConstraint = stackView.autoSetDimension(.height, toSize: itemSize)
        stackView.layoutIfNeeded()
        self.stackView = stackView

        UIView.performWithoutAnimation {
            self.layoutIfNeeded()
        }

        // Unhide only if view is hidden automatically.
        if hidesAutomatically {
            if animated && isHiddenInStackView {
                UIView.animate(withDuration: duration) {
                    self.isHiddenInStackView = false
                    self.superview?.layoutIfNeeded()
                }
            } else {
                isHiddenInStackView = false
            }
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

        scrollView.addSubview(stackView)
        addConstraints([
            NSLayoutConstraint(
                item: stackView, attribute: .leading, relatedBy: .equal,
                toItem: scrollView.contentLayoutGuide, attribute: .leading, multiplier: 1, constant: 0
            ),
            NSLayoutConstraint(
                item: stackView, attribute: .top, relatedBy: .equal,
                toItem: scrollView.contentLayoutGuide, attribute: .top, multiplier: 1, constant: 0
            ),
            NSLayoutConstraint(
                item: stackView, attribute: .trailing, relatedBy: .equal,
                toItem: scrollView.contentLayoutGuide, attribute: .trailing, multiplier: 1, constant: 0
            ),
            NSLayoutConstraint(
                item: stackView, attribute: .bottom, relatedBy: .equal,
                toItem: scrollView.contentLayoutGuide, attribute: .bottom, multiplier: 1, constant: 0
            ),
            NSLayoutConstraint(
                item: stackView, attribute: .height, relatedBy: .equal,
                toItem: scrollView, attribute: .height, multiplier: 1, constant: 0
            )
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
        scrollToFocusedCell(animated: animated)
    }

    private func scrollToFocusedCell(animated: Bool) {
        guard let focusedCell = cellViews.first(where: { $0.isCellFocused }) else { return }
        let cellFrame = focusedCell.convert(focusedCell.bounds, to: scrollView)
        scrollView.scrollRectToVisible(cellFrame, animated: animated)
    }
}
