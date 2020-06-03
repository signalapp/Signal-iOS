//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

public enum PhotoGridItemType {
    case photo, animated, video
}

public protocol PhotoGridItem: class {
    var type: PhotoGridItemType { get }
    func asyncThumbnail(completion: @escaping (UIImage?) -> Void) -> UIImage?
}

public class PhotoGridViewCell: UICollectionViewCell {

    static let reuseIdentifier = "PhotoGridViewCell"

    public let imageView: UIImageView

    private let contentTypeBadgeView: UIImageView
    private let unselectedBadgeView: UIView
    private let selectedBadgeView: UIImageView

    private let highlightedMaskView: UIView
    private let selectedMaskView: UIView

    var item: PhotoGridItem?

    private static let videoBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_video")
    private static let animatedBadgeImage = #imageLiteral(resourceName: "ic_gallery_badge_gif")
    private static let selectedBadgeImage = #imageLiteral(resourceName: "image_editor_checkmark_full").withRenderingMode(.alwaysTemplate)
    public var loadingColor = Theme.washColor

    override public var isSelected: Bool {
        didSet {
            updateSelectionState()
        }
    }

    public var allowsMultipleSelection: Bool = false {
        didSet {
            updateSelectionState()
        }
    }

    func updateSelectionState() {
        if isSelected {
            unselectedBadgeView.isHidden = true
            selectedBadgeView.isHidden = false
            selectedMaskView.isHidden = false
        } else if allowsMultipleSelection {
            unselectedBadgeView.isHidden = false
            selectedBadgeView.isHidden = true
            selectedMaskView.isHidden = true
        } else {
            unselectedBadgeView.isHidden = true
            selectedBadgeView.isHidden = true
            selectedMaskView.isHidden = true
        }
    }

    override public var isHighlighted: Bool {
        didSet {
            self.highlightedMaskView.isHidden = !self.isHighlighted
        }
    }

    override init(frame: CGRect) {
        self.imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill

        self.contentTypeBadgeView = UIImageView()
        contentTypeBadgeView.isHidden = true

        self.selectedBadgeView = UIImageView()
        selectedBadgeView.image = PhotoGridViewCell.selectedBadgeImage
        selectedBadgeView.isHidden = true
        selectedBadgeView.tintColor = .white

        self.unselectedBadgeView = CircleView()
        unselectedBadgeView.backgroundColor = .clear
        unselectedBadgeView.layer.borderWidth = 0.5
        unselectedBadgeView.layer.borderColor = UIColor.white.cgColor
        selectedBadgeView.isHidden = true

        self.highlightedMaskView = UIView()
        highlightedMaskView.alpha = 0.2
        highlightedMaskView.backgroundColor = Theme.darkThemePrimaryColor
        highlightedMaskView.isHidden = true

        self.selectedMaskView = UIView()
        selectedMaskView.alpha = 0.3
        selectedMaskView.backgroundColor = Theme.darkThemeBackgroundColor
        selectedMaskView.isHidden = true

        super.init(frame: frame)

        self.clipsToBounds = true

        self.contentView.addSubview(imageView)
        self.contentView.addSubview(contentTypeBadgeView)
        self.contentView.addSubview(highlightedMaskView)
        self.contentView.addSubview(selectedMaskView)
        self.contentView.addSubview(unselectedBadgeView)
        self.contentView.addSubview(selectedBadgeView)

        imageView.autoPinEdgesToSuperviewEdges()
        highlightedMaskView.autoPinEdgesToSuperviewEdges()
        selectedMaskView.autoPinEdgesToSuperviewEdges()

        // Note assets were rendered to match exactly. We don't want to re-size with
        // content mode lest they become less legible.
        let kContentTypeBadgeSize = CGSize(square: 12)
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .leading, withInset: 3)
        contentTypeBadgeView.autoPinEdge(toSuperviewEdge: .bottom, withInset: 3)
        contentTypeBadgeView.autoSetDimensions(to: kContentTypeBadgeSize)

        let kUnselectedBadgeSize = CGSize(square: 22)
        unselectedBadgeView.autoPinEdge(toSuperviewEdge: .trailing, withInset: 4)
        unselectedBadgeView.autoPinEdge(toSuperviewEdge: .top, withInset: 4)
        unselectedBadgeView.autoSetDimensions(to: kUnselectedBadgeSize)

        let kSelectedBadgeSize = CGSize(square: 22)
        selectedBadgeView.autoSetDimensions(to: kSelectedBadgeSize)
        selectedBadgeView.autoAlignAxis(.vertical, toSameAxisOf: unselectedBadgeView)
        selectedBadgeView.autoAlignAxis(.horizontal, toSameAxisOf: unselectedBadgeView)
    }

    @available(*, unavailable, message: "Unimplemented")
    required public init?(coder aDecoder: NSCoder) {
        notImplemented()
    }

    var image: UIImage? {
        get { return imageView.image }
        set {
            imageView.image = newValue
            imageView.backgroundColor = newValue == nil ? loadingColor : .clear
        }
    }

    var contentTypeBadgeImage: UIImage? {
        get { return contentTypeBadgeView.image }
        set {
            contentTypeBadgeView.image = newValue
            contentTypeBadgeView.isHidden = newValue == nil
        }
    }

    public func configure(item: PhotoGridItem) {
        self.item = item

        // PHCachingImageManager returns multiple progressively better
        // thumbnails in the async block. We want to avoid calling
        // `configure(item:)` multiple times because the high-quality image eventually applied
        // last time it was called will be momentarily replaced by a progression of lower
        // quality images.
        image = item.asyncThumbnail { [weak self] image in
            guard let self = self else { return }

            guard let currentItem = self.item else {
                return
            }

            guard currentItem === item else {
                return
            }

            if image == nil {
                Logger.debug("image == nil")
            }
            self.image = image
        }

        switch item.type {
        case .video:
            self.contentTypeBadgeImage = PhotoGridViewCell.videoBadgeImage
        case .animated:
            self.contentTypeBadgeImage = PhotoGridViewCell.animatedBadgeImage
        case .photo:
            self.contentTypeBadgeImage = nil
        }
    }

    override public func prepareForReuse() {
        super.prepareForReuse()

        item = nil
        imageView.image = nil
        contentTypeBadgeView.isHidden = true
        highlightedMaskView.isHidden = true
        selectedMaskView.isHidden = true
        selectedBadgeView.isHidden = true
        unselectedBadgeView.isHidden = true
    }
}
