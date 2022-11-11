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

public class GalleryRailCellView: UIView {

    weak var delegate: GalleryRailCellViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = .zero
        clipsToBounds = false
        addSubview(contentContainer)
        contentContainer.autoPinEdgesToSuperviewMargins()
        contentContainer.layer.cornerRadius = 10

        dimmerView.layer.cornerRadius = 10
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
        self.delegate?.didTapGalleryRailCellView(self)
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

    private(set) var isSelected: Bool = false

    func setIsSelected(_ isSelected: Bool) {
        self.isSelected = isSelected
        dimmerView.layer.borderWidth = isSelected ? 2 : 1.5
        dimmerView.layer.borderColor = isSelected ? tintColor.cgColor : UIColor.ows_white.cgColor
    }

    // MARK: Subview Helpers

    let contentContainer: UIView = {
        let view = UIView()
        view.autoPinToSquareAspectRatio()
        view.clipsToBounds = true
        return view
    }()

    let dimmerView: UIView = {
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

    public var cellViews: [GalleryRailCellView] = []

    var cellViewItems: [GalleryRailItem] {
        cellViews.compactMap { $0.item }
    }

    /**
     * If enabled, `GalleryRailView` will hide itself if there is less than two items.
     */
    var hidesAutomatically = true

    // MARK: Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        preservesSuperviewLayoutMargins = true
        addSubview(scrollView)
        scrollView.clipsToBounds = false
        scrollView.layoutMargins = .zero
        scrollView.autoPinEdgesToSuperviewMargins()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public

    typealias AnimationBlock = () -> Void
    typealias AnimationCompletionBlock = (Bool) -> Void

    // UIView.animate(), takes an "animated" flag which disables animations.
    private func animate(animationDuration: TimeInterval,
                         animated: Bool,
                         animations: @escaping AnimationBlock,
                         completion: AnimationCompletionBlock? = nil) {
        guard animated else {
            animations()
            completion?(true)
            return
        }
        UIView.animate(withDuration: animationDuration, animations: animations, completion: completion)
    }

    public func configureCellViews(itemProvider: GalleryRailItemProvider,
                                   focusedItem: GalleryRailItem,
                                   cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView,
                                   animated: Bool = true) {
        let animationDuration: TimeInterval = 0.2

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

        if itemProvider === self.itemProvider, areRailItemsIdentical(itemProvider.railItems, self.cellViewItems) {
            animate(animationDuration: animationDuration,
                    animated: animated,
                    animations: {
                self.updateFocusedItem(focusedItem)
            })
            return
        }

        self.itemProvider = itemProvider

        guard itemProvider.railItems.count > 1 || !hidesAutomatically else {
            let cellViews = scrollView.subviews

            animate(animationDuration: animationDuration, animated: animated,
                    animations: {
                cellViews.forEach { $0.isHidden = true }
                self.alpha = 0
            },
                    completion: { _ in
                cellViews.forEach { $0.removeFromSuperview() }
                self.isHidden = true
                self.alpha = 1
            })
            self.cellViews = []
            return
        }

        scrollView.subviews.forEach { $0.removeFromSuperview() }

        if hidesAutomatically {
            animate(animationDuration: animationDuration,
                    animated: true,
                    animations: {
                self.isHidden = false
            })
        }

        let cellViews = buildCellViews(items: itemProvider.railItems, cellViewBuilder: cellViewBuilder)
        self.cellViews = cellViews
        let stackView = UIStackView(arrangedSubviews: cellViews)
        stackView.axis = .horizontal
        stackView.spacing = 4
        stackView.clipsToBounds = false

        scrollView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewEdges()
        stackView.autoMatch(.height, to: .height, of: scrollView)

        updateFocusedItem(focusedItem)
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
        return scrollView
    }()

    private func buildCellViews(items: [GalleryRailItem],
                                cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView) -> [GalleryRailCellView] {
        return items.map { item in
            let cellView = cellViewBuilder(item)
            cellView.configure(item: item, delegate: self)
            return cellView
        }
    }

    enum ScrollFocusMode {
        case keepCentered, keepWithinBounds
    }
    var scrollFocusMode: ScrollFocusMode = .keepCentered
    func updateFocusedItem(_ focusedItem: GalleryRailItem) {
        var selectedCellView: GalleryRailCellView?
        cellViews.forEach { cellView in
            if let item = cellView.item, item.isEqualToGalleryRailItem(focusedItem) {
                assert(selectedCellView == nil)
                selectedCellView = cellView
                cellView.setIsSelected(true)
            } else {
                cellView.setIsSelected(false)
            }
        }

        self.layoutIfNeeded()
        switch scrollFocusMode {
        case .keepCentered:
            guard let selectedCell = selectedCellView else {
                owsFailDebug("selectedCell was unexpectedly nil")
                return
            }

            let cellViewCenter = selectedCell.superview!.convert(selectedCell.center, to: scrollView)
            let additionalInset = scrollView.center.x - cellViewCenter.x

            var inset = scrollView.contentInset
            inset.left = additionalInset
            scrollView.contentInset = inset

            var offset = scrollView.contentOffset
            offset.x = -additionalInset
            scrollView.contentOffset = offset
        case .keepWithinBounds:
            guard let selectedCell = selectedCellView else {
                owsFailDebug("selectedCell was unexpectedly nil")
                return
            }

            let cellFrame = selectedCell.superview!.convert(selectedCell.frame, to: scrollView)

            scrollView.scrollRectToVisible(cellFrame, animated: true)
        }
    }
}
