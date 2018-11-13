//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import PromiseKit

protocol GalleryRailItemProvider: class {
    var railItems: [GalleryRailItem] { get }
}

protocol GalleryRailItem: class {
    func getRailImage() -> Guarantee<UIImage>
    var aspectRatio: CGFloat { get }
}

extension CGSize {
    var aspectRatio: CGFloat {
        guard self.height > 0 else {
            return 0
        }

        return self.width / self.height
    }
}

extension MediaGalleryItem: GalleryRailItem {
    var aspectRatio: CGFloat {
        return self.imageSize.aspectRatio
    }

    func getRailImage() -> Guarantee<UIImage> {
        let (guarantee, fulfill) = Guarantee<UIImage>.pending()
        if let image = self.thumbnailImage(async: { fulfill($0) }) {
            fulfill(image)
        }

        return guarantee
    }
}

extension MediaGalleryAlbum: GalleryRailItemProvider {
    var railItems: [GalleryRailItem] {
        return self.items
    }
}

protocol GalleryRailCellViewDelegate: class {
    func didTapGalleryRailCellView(_ galleryRailCellView: GalleryRailCellView)
}

class GalleryRailCellView: UIView {

    weak var delegate: GalleryRailCellViewDelegate?

    override init(frame: CGRect) {
        super.init(frame: frame)

        layoutMargins = .zero
        self.clipsToBounds = true
        adjustAspectRatio(isSelected: isSelected)
        addSubview(imageView)
        imageView.autoPinEdgesToSuperviewMargins()

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(didTap(sender:)))
        addGestureRecognizer(tapGesture)
    }

    required init?(coder aDecoder: NSCoder) {
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

        item.getRailImage().done { image in
            guard self.item === item else { return }

            self.imageView.image = image
            }.retainUntilComplete()
    }

    // MARK: Selected

    private(set) var isSelected: Bool = false

    func setIsSelected(_ isSelected: Bool) {
        self.isSelected = isSelected
        adjustAspectRatio(isSelected: isSelected)
        if isSelected {
            self.layoutMargins = UIEdgeInsets(top: 0, left: 3, bottom: 0, right: 3)
        } else {
            self.layoutMargins = .zero
        }
    }

    // MARK: Subview Helpers

    var aspectRatioConstraint: NSLayoutConstraint?
    func adjustAspectRatio(isSelected: Bool) {
        if let oldConstraint = aspectRatioConstraint {
            NSLayoutConstraint.deactivate([oldConstraint])
        }

        if isSelected, let itemAspectRatio = item?.aspectRatio {
            aspectRatioConstraint = imageView.autoPin(toAspectRatio: itemAspectRatio)
        } else {
            // Portrait mode AR by default
            let kDefaultAspectRatio: CGFloat = 9.0 / 16.0
            aspectRatioConstraint = imageView.autoPin(toAspectRatio: kDefaultAspectRatio)
        }
    }

    let imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        return imageView
    }()
}

protocol GalleryRailViewDelegate: class {
    func galleryRailView(_ galleryRailView: GalleryRailView, didTapItem imageRailItem: GalleryRailItem)
}

class GalleryRailView: UIView, GalleryRailCellViewDelegate {

    weak var delegate: GalleryRailViewDelegate?

    // MARK: Initializers

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(scrollView)
        scrollView.layoutMargins = .zero
        scrollView.autoPinEdgesToSuperviewMargins()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public

    public func configure(itemProvider: GalleryRailItemProvider?, focusedItem: GalleryRailItem?) {
        let animationDuration: TimeInterval = 0.2

        guard let itemProvider = itemProvider else {
            UIView.animate(withDuration: animationDuration) {
                self.isHidden = true
            }
            return
        }

        let areRailItemsIdentical = { (lhs: [GalleryRailItem], rhs: [GalleryRailItem]) -> Bool in
            guard lhs.count == rhs.count else {
                return false
            }
            for (index, element) in lhs.enumerated() {
                guard element === rhs[index] else {
                    return false
                }
            }
            return true
        }

        if itemProvider === self.itemProvider, areRailItemsIdentical(itemProvider.railItems, self.cellViewItems) {
            UIView.animate(withDuration: animationDuration) {
                self.updateFocusedItem(focusedItem)
                self.layoutIfNeeded()
            }
        }

        self.itemProvider = itemProvider
        scrollView.subviews.forEach { $0.removeFromSuperview() }

        guard itemProvider.railItems.count > 1 else {
            UIView.animate(withDuration: animationDuration) {
                self.isHidden = true
            }
            return
        }

        UIView.animate(withDuration: animationDuration) {
            self.isHidden = false
        }

        let cellViews = buildCellViews(items: itemProvider.railItems)
        self.cellViews = cellViews
        let stackView = UIStackView(arrangedSubviews: cellViews)
        stackView.axis = .horizontal
        stackView.spacing = 4

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

    private func buildCellViews(items: [GalleryRailItem]) -> [GalleryRailCellView] {
        return items.map { item in
            let cellView = GalleryRailCellView()
            cellView.configure(item: item, delegate: self)
            return cellView
        }
    }

    var cellViews: [GalleryRailCellView] = []
    var cellViewItems: [GalleryRailItem] {
        get { return cellViews.compactMap { $0.item } }
    }
    func updateFocusedItem(_ focusedItem: GalleryRailItem?) {
        var selectedCellView: GalleryRailCellView?
        cellViews.forEach { cellView in
            if cellView.item === focusedItem {
                assert(selectedCellView == nil)
                selectedCellView = cellView
                cellView.setIsSelected(true)
            } else {
                cellView.setIsSelected(false)
            }
        }

        self.layoutIfNeeded()
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
    }
}
