// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import UIKit
import PromiseKit
import SessionUIKit

// MARK: - GalleryRailItem

public protocol GalleryRailItem {
    func buildRailItemView() -> UIView
    func isEqual(to other: GalleryRailItem?) -> Bool
}

// MARK: - GalleryRailCellViewDelegate

protocol GalleryRailCellViewDelegate: AnyObject {
    func didTapGalleryRailCellView(_ galleryRailCellView: GalleryRailCellView)
}

// MARK: - GalleryRailCellView

public class GalleryRailCellView: UIView {
    public let cellBorderWidth: CGFloat = 3
    public var item: GalleryRailItem?
    fileprivate weak var delegate: GalleryRailCellViewDelegate?
    
    private(set) var isSelected: Bool = false
    
    // MARK: - UI
    
    let contentContainer: UIView = {
        let view = UIView()
        view.autoPinToSquareAspectRatio()
        view.clipsToBounds = true

        return view
    }()
    
    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = .zero
        clipsToBounds = false
        addSubview(contentContainer)
        contentContainer.autoPinEdgesToSuperviewMargins()
        contentContainer.layer.cornerRadius = 4.8

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(sender:)))
        addGestureRecognizer(tapGesture)
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions

    @objc
    func didTap(sender: UITapGestureRecognizer) {
        self.delegate?.didTapGalleryRailCellView(self)
    }

    // MARK: Content

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

    // MARK: - Selected

    func setIsSelected(_ isSelected: Bool) {
        self.isSelected = isSelected

        // Reserve space for the selection border whether or not the cell is selected.
        layoutMargins = UIEdgeInsets(top: 0, left: cellBorderWidth, bottom: 0, right: cellBorderWidth)

        if isSelected {
            contentContainer.themeBorderColor = .primary
            contentContainer.layer.borderWidth = cellBorderWidth
        }
        else {
            contentContainer.layer.borderWidth = 0
        }
    }
}

// MARK: - GalleryRailViewDelegate

public protocol GalleryRailViewDelegate: AnyObject {
    func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem)
}

// MARK: - GalleryRailView

public class GalleryRailView: UIView, GalleryRailCellViewDelegate {
    public enum ScrollFocusMode {
        case keepCentered
        case keepWithinBounds
    }

    public var scrollFocusMode: ScrollFocusMode = .keepCentered
    public var cellViews: [GalleryRailCellView] = []
    public weak var delegate: GalleryRailViewDelegate?
    
    private var album: [GalleryRailItem]?
    private var oldSize: CGSize = .zero

    var cellViewItems: [GalleryRailItem] {
        get { return cellViews.compactMap { $0.item } }
    }

    // MARK: - Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        clipsToBounds = false
        
        addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewMargins()
        
        scrollView.addSubview(stackClippingView)
        stackClippingView.addSubview(stackView)
        
        stackClippingView.autoPinEdgesToSuperviewEdges()
        stackClippingView.autoMatch(.height, to: .height, of: scrollView)
        stackView.autoPinEdgesToSuperviewEdges()
    }

    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - UI
    
    private let scrollView: UIScrollView = {
        let result: UIScrollView = UIScrollView()
        result.clipsToBounds = false
        result.layoutMargins = .zero
        result.isScrollEnabled = true
        result.scrollIndicatorInsets = UIEdgeInsets(top: 0, leading: 0, bottom: -10, trailing: 0)
        
        return result
    }()
    
    private let stackClippingView: UIView = {
        let result: UIView = UIView()
        result.clipsToBounds = true
        
        return result
    }()
    
    private let stackView: UIStackView = {
        let result: UIStackView = UIStackView()
        result.clipsToBounds = false
        result.axis = .horizontal
        result.spacing = 0
        
        return result
    }()

    // MARK: - Public

    public func configureCellViews(album: [GalleryRailItem], focusedItem: GalleryRailItem?, cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView) {
        let animationDuration: TimeInterval = 0.2
        let zippedItems = zip(album, self.cellViewItems)

        // Check if the album has changed
        guard
            album.count != self.cellViewItems.count ||
            zippedItems.contains(where: { lhs, rhs in !lhs.isEqual(to: rhs) })
        else {
            UIView.animate(withDuration: animationDuration) {
                self.updateFocusedItem(focusedItem)
                self.layoutIfNeeded()
            }
            return
        }

        // If so update to the new album
        self.album = album

        // Check if there are multiple items in the album (if not then just slide it away)
        guard album.count > 1 else {
            let oldFrame: CGRect = self.stackView.frame

            UIView.animate(
                withDuration: animationDuration,
                animations: { [weak self] in
                    self?.isHidden = true
                    self?.stackView.frame = oldFrame.offsetBy(
                        dx: 0,
                        dy: oldFrame.height
                    )
                },
                completion: { [weak self] _ in
                    self?.stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
                    self?.stackView.frame = oldFrame
                    self?.cellViews = []
                }
            )
            return
        }
        
        // Otherwise slide it away, recreate it and then slide it back
        let newCellViews: [GalleryRailCellView] = buildCellViews(
            items: album,
            cellViewBuilder: cellViewBuilder
        )
        
        let animateOut: ((CGRect, @escaping (CGRect) -> CGRect, @escaping (CGRect) -> ()) -> ()) = { [weak self] oldFrame, layoutNewItems, animateIn in
            UIView.animate(
                withDuration: (animationDuration / 2),
                delay: 0,
                options: .curveEaseIn,
                animations: {
                    self?.stackView.frame = oldFrame.offsetBy(
                        dx: 0,
                        dy: oldFrame.height
                    )
                },
                completion: { _ in
                    let updatedOldFrame: CGRect = layoutNewItems(oldFrame)
                    animateIn(updatedOldFrame)
                }
            )
        }
        let layoutNewItems: (CGRect) -> CGRect = { [weak self] oldFrame -> CGRect in
            var updatedOldFrame: CGRect = oldFrame
            
            // Update the UI (need to re-offset it as the position gets reset during
            // during these changes)
            UIView.performWithoutAnimation {
                self?.stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
                newCellViews.forEach { cellView in
                    self?.stackView.addArrangedSubview(cellView)
                }
                self?.cellViews = newCellViews
                
                self?.stackView.layoutIfNeeded()
                self?.updateFocusedItem(focusedItem)
                self?.isHidden = false
                
                updatedOldFrame = (self?.stackView.frame)
                    .defaulting(to: oldFrame)
                self?.stackView.frame = updatedOldFrame.offsetBy(
                    dx: 0,
                    dy: oldFrame.height
                )
            }
            
            return updatedOldFrame
        }
        let animateIn: (CGRect) -> () = { [weak self] oldFrame in
            UIView.animate(
                withDuration: (animationDuration / 2),
                delay: 0,
                options: .curveEaseOut,
                animations: { [weak self] in
                    self?.stackView.frame = oldFrame
                    self?.isHidden = false
                },
                completion: nil
            )
        }
        
        // If we don't have arranged subviews already we can skip the 'animateOut'
        guard !self.stackView.arrangedSubviews.isEmpty else {
            let updatedOldFrame: CGRect = layoutNewItems(self.stackView.frame)
            
            // Hide self again because it would have previously been hidden and we want to
            // properly animate it's appearance
            self.isHidden = true
            
            animateIn(updatedOldFrame)
            return
        }

        animateOut(self.stackView.frame, layoutNewItems, animateIn)
    }

    // MARK: - GalleryRailCellViewDelegate

    func didTapGalleryRailCellView(_ galleryRailCellView: GalleryRailCellView) {
        guard let item = galleryRailCellView.item else { return }

        delegate?.galleryRailView(self, didTapItem: item)
    }

    // MARK: - Subview Helpers
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        guard self.bounds.size != self.oldSize else { return }
        
        self.oldSize = self.bounds.size
        
        // If the bounds of the biew changed then update the focused item to ensure the
        // alignment isn't broken
        if let focusedItem: GalleryRailItem = self.cellViews.first(where: { $0.isSelected })?.item {
            self.updateFocusedItem(focusedItem)
        }
    }

    private func buildCellViews(items: [GalleryRailItem], cellViewBuilder: (GalleryRailItem) -> GalleryRailCellView) -> [GalleryRailCellView] {
        return items.map { item in
            let cellView = cellViewBuilder(item)
            cellView.configure(item: item, delegate: self)
            return cellView
        }
    }

    func updateFocusedItem(_ focusedItem: GalleryRailItem?) {
        let selectedCellView: GalleryRailCellView? = cellViews.first(where: { cellView -> Bool in
            (cellView.item?.isEqual(to: focusedItem) == true)
        })
        
        cellViews.forEach { $0.setIsSelected(false) }
        selectedCellView?.setIsSelected(true)

        self.layoutIfNeeded()
        self.stackView.layoutIfNeeded()
        
        switch scrollFocusMode {
            case .keepCentered:
                guard
                    let selectedCell: UIView = selectedCellView,
                    let selectedCellSuperview: UIView = selectedCell.superview
                else { return }

                let cellViewCenter: CGPoint = selectedCellSuperview.convert(selectedCell.center, to: scrollView)
                let additionalInset: CGFloat = ((scrollView.frame.width / 2) - cellViewCenter.x)
                
                var inset: UIEdgeInsets = scrollView.contentInset
                inset.left = additionalInset
                scrollView.contentInset = inset

                var offset: CGPoint = scrollView.contentOffset
                offset.x = -additionalInset
                scrollView.contentOffset = offset
                
            case .keepWithinBounds:
                guard
                    let selectedCell: UIView = selectedCellView,
                    let selectedCellSuperview: UIView = selectedCell.superview
                else { return }

                let cellFrame: CGRect = selectedCellSuperview.convert(selectedCell.frame, to: scrollView)
                scrollView.scrollRectToVisible(cellFrame, animated: true)
        }
    }
}
